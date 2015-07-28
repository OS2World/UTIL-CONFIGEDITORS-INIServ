(**************************************************************************)
(*                                                                        *)
(*  INIServe server for remote access to INI/TNI files.                   *)
(*  Copyright (C) 2014   Peter Moylan                                     *)
(*                                                                        *)
(*  This program is free software: you can redistribute it and/or modify  *)
(*  it under the terms of the GNU General Public License as published by  *)
(*  the Free Software Foundation, either version 3 of the License, or     *)
(*  (at your option) any later version.                                   *)
(*                                                                        *)
(*  This program is distributed in the hope that it will be useful,       *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *)
(*  GNU General Public License for more details.                          *)
(*                                                                        *)
(*  You should have received a copy of the GNU General Public License     *)
(*  along with this program.  If not, see <http://www.gnu.org/licenses/>. *)
(*                                                                        *)
(*  To contact author:   http://www.pmoylan.org   peter@pmoylan.org       *)
(*                                                                        *)
(**************************************************************************)

IMPLEMENTATION MODULE INICommands;

        (********************************************************)
        (*                                                      *)
        (*       Command interpreter for INIServe               *)
        (*                                                      *)
        (*  Programmer:         P. Moylan                       *)
        (*  Started:            24 May 1998                     *)
        (*  Last edited:        20 July 2015                    *)
        (*  Status:             Working                         *)
        (*                                                      *)
        (********************************************************)

(********************************************************************************)
(*                             COMMAND SUMMARY                                  *)
(********************************************************************************)
(*                                                                              *)
(*      A                  set application          WORKING                     *)
(*      C                  change directory         WORKING                     *)
(*      D                  delete current entry     WORKING                     *)
(*      E<string>          post event semaphore     DONE, UNTESTED              *)
(*      F                  select file to edit      WORKING                     *)
(*      K                  set key                  WORKING                     *)
(*      L<string>          list directory           WORKING                     *)
(*      M<string>          make new directory       WORKING                     *)
(*      O<val>,<val>       offset and size (for V & W commands) WORKING, I THINK *)
(*      P<string>          password                 WORKING                     *)
(*      Q                  quit                     WORKING                     *)
(*      R                  relocate                 DONE, UNTESTED              *)
(*      S                  return size of current item  WORKING                 *)
(*      T                  truncated size           DONE BUT UNTESTED           *)
(*      V                  return value of current item  WORKING                *)
(*      W<hexdata>         store new value for current item  WORKING            *)
(*      X<string>          delete file or directory DONE, UNTESTED              *)
(*                                                                              *)
(********************************************************************************)

FROM SYSTEM IMPORT
    (* type *)  CARD8,
    (* proc *)  ADR;

IMPORT INIData, Strings, STextIO, OS2;

FROM Storage IMPORT
    (* proc *)  ALLOCATE, DEALLOCATE;

FROM LowLevel IMPORT
    (* proc *)  EVAL;

FROM Hexadecimal IMPORT
    (* proc *)  GetHex2, GetHex;

FROM Sockets IMPORT
    (* type *)  Socket,
    (* proc *)  send;

FROM INIMisc IMPORT
    (* proc *)  AddEOL, OpenINIFile;

FROM INIData IMPORT
    (* type *)  HINI,
    (* proc *)  INIGetString;

FROM INIFiles IMPORT
    (* type *)  FilenameString,
    (* proc *)  ListDrives, ListDirectory, SetDirectory, MakeDirectory,
                MakeFilename, MoveFile, FileDelete;

(********************************************************************************)

CONST Nul = CHR(0);
      testing = FALSE;

TYPE
    BufferPointer = POINTER TO ARRAY [0..MAX(CARDINAL) DIV 4] OF CARD8;

    ClientState = (Idle, LoggedIn, MustExit);

    (* The session record.  The fields are:                             *)
    (*     ID          a session identifier for transaction logging     *)
    (*     socket      The command socket                               *)
    (*     state       To track whether the user is currently logged in *)
    (*     AtRoot      TRUE if we're currently in the superdirectory    *)
    (*     CurrentDir  The current directory for the session            *)
    (*                   Always ends with a '\'.                        *)
    (*     filename    the file being edited                            *)
    (*     Application,                                                 *)
    (*        Key      the INI file keys                                *)
    (*     offset      starting point for V & W commands                *)
    (*     limit       max bytes to transfer for V & W commands         *)

    Session = POINTER TO
                  RECORD
                      socket: Socket;
                      state: ClientState;
                      AtRoot: BOOLEAN;
                      CurrentDir: FilenameString;
                      filename: FilenameString;
                      Application: FilenameString;
                      Key: FilenameString;
                      offset, limit: CARDINAL;
                  END (*RECORD*);

(********************************************************************************)
(*                         STARTING A NEW SESSION                               *)
(********************************************************************************)

PROCEDURE OpenSession (CommandSocket: Socket): Session;

    (* Creates a new session state record.  *)

    VAR result: Session;

    BEGIN
        NEW (result);
        WITH result^ DO
            socket := CommandSocket;
            state := Idle;
            AtRoot := TRUE;
            CurrentDir := "\";
            filename := "";
            offset := 0;
            limit := MAX(CARDINAL);
        END (*WITH*);
        RETURN result;
    END OpenSession;

(********************************************************************************)

PROCEDURE CloseSession (S: Session);

    (* Destroys the session state record. *)

    BEGIN
        DISPOSE (S);
    END CloseSession;

(********************************************************************************)
(*                            INI FILE OPERATIONS                               *)
(********************************************************************************)

PROCEDURE OpenCurrentINIFile (session: Session): HINI;

    (* Opens the current INI file for this session. *)

    VAR name: FilenameString;  AtRoot: BOOLEAN;

    BEGIN
        name := session^.CurrentDir;
        Strings.Append (session^.filename, name);
        MakeFilename (session^.CurrentDir, session^.filename, name, AtRoot);
        IF AtRoot THEN
            RETURN NIL;
        ELSE
            RETURN OpenINIFile (name);
        END (*IF*);
    END OpenCurrentINIFile;

(********************************************************************************)

PROCEDURE ItemSize (hini: HINI;  session: Session;
                                VAR (*OUT*) size: CARDINAL): BOOLEAN;

    (* Sets size to the size in bytes of the current INI file entry, or returns *)
    (* FALSE if there is no such entry.                                         *)

    BEGIN
        RETURN INIData.ItemSize (hini, session^.Application,
                                   session^.Key, size);
    END ItemSize;

(********************************************************************************)

PROCEDURE LoadValue (hini: HINI;  session: Session;
                     VAR (*OUT*) result: ARRAY OF CARD8;  size: CARDINAL);

    BEGIN
        EVAL (INIData.INIGetTrusted (hini, session^.Application, session^.Key, result, size));
    END LoadValue;

(********************************************************************************)

PROCEDURE StoreValue (hini: HINI;  session: Session;
                     VAR (*IN*) data: ARRAY OF CARD8;  size: CARDINAL): BOOLEAN;

    (* Writes back "data" as the new value for the currently selected INI file  *)
    (* entry.                                                                   *)

    BEGIN
        IF INIData.INIValid(hini) THEN
            INIData.INIPutBinary (hini, session^.Application, session^.Key, data, size);
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END (*IF*);
    END StoreValue;

(********************************************************************************)

PROCEDURE DeleteKey (hini: HINI;  session: Session): BOOLEAN;

    (* Deletes the currently selected INI file entry.  *)

    BEGIN
        INIData.INIDeleteKey (hini, session^.Application, session^.Key);
        RETURN TRUE;
    END DeleteKey;

(********************************************************************************)
(*                       SENDING REPLY BACK TO CLIENT                           *)
(********************************************************************************)

PROCEDURE Reply2 (session: Session;  message1, message2: ARRAY OF CHAR);

    (* Sends all of message1, followed by message2, followed by end-of-line.    *)
    (* If the operation fails, session^.state is set to MustExit.               *)

    VAR buffer: ARRAY [0..511] OF CHAR;  length: CARDINAL;

    BEGIN
        Strings.Assign (message1, buffer);
        Strings.Append (message2, buffer);
        length := AddEOL (buffer);
        IF send (session^.socket, buffer, length, 0) = MAX(CARDINAL) THEN
            session^.state := MustExit;
        END (*IF*);
    END Reply2;

(********************************************************************************)

PROCEDURE Reply (session: Session;  message: ARRAY OF CHAR);

    (* Like Reply2, except that there is no message2. *)

    VAR buffer: ARRAY [0..511] OF CHAR;  length: CARDINAL;

    BEGIN
        Strings.Assign (message, buffer);
        length := AddEOL (buffer);
        IF send (session^.socket, buffer, length, 0) = MAX(CARDINAL) THEN
            session^.state := MustExit;
        END (*IF*);
    END Reply;

(********************************************************************************)

PROCEDURE AppendHex1 (value: CARDINAL;  VAR (*INOUT*) buffer: ARRAY OF CHAR);

    (* Appends a one-digit hexadecimal number to the buffer. *)

    VAR j: CARDINAL;  ch: CHAR;

    BEGIN
        IF value < 10 THEN
            ch := CHR(ORD('0') + value);
        ELSE
            ch := CHR(ORD('A') + value - 10);
        END (*IF*);
        j := Strings.Length (buffer);
        IF j <= HIGH(buffer) THEN
            buffer[j] := ch;  INC(j);
        END (*IF*);
        IF j <= HIGH(buffer) THEN
            buffer[j] := CHR(0);
        END (*IF*);
    END AppendHex1;

(********************************************************************************)

PROCEDURE AppendHex2 (value: CARDINAL;  VAR (*INOUT*) buffer: ARRAY OF CHAR);

    (* Appends a two-digit hexadecimal number. *)

    BEGIN
        AppendHex1 (value DIV 16, buffer);
        AppendHex1 (value MOD 16, buffer);
    END AppendHex2;

(********************************************************************************)

PROCEDURE AppendHexValue (value: CARDINAL;  VAR (*INOUT*) buffer: ARRAY OF CHAR);

    (* Converts value to hexadecimal and appends it to the buffer. *)

    CONST radix = 16;

    BEGIN
        IF value >= radix THEN
            AppendHexValue (value DIV radix, buffer);
        END (*IF*);
        AppendHex1 (value MOD radix, buffer);
    END AppendHexValue;

(********************************************************************************)

PROCEDURE AppendByteString (p: BufferPointer;  start, amount: CARDINAL;
                                          VAR (*INOUT*) buffer: ARRAY OF CHAR);

    (* Converts 'amount' bytes of data to hexadecimal and appends it to the buffer. *)

    VAR j: CARDINAL;

    BEGIN
        IF amount > 0 THEN
            FOR j := start TO start+amount-1 DO
                AppendHex2 (p^[j], buffer);
            END (*FOR*);
        END (*IF*);
    END AppendByteString;

(********************************************************************************)

PROCEDURE ReturnHex (session: Session;  value: CARDINAL);

    (* Returns a '+', followed by the hexadecimal coding of value, *)
    (* followed by end-of-line.                                    *)

    VAR S: Socket;
        ReplyBuffer: ARRAY [0..10] OF CHAR;  sendsize: CARDINAL;

    BEGIN
        S := session^.socket;
        ReplyBuffer := "+";
        AppendHexValue (value, ReplyBuffer);
        sendsize := AddEOL (ReplyBuffer);
        IF send (S, ReplyBuffer, sendsize, 0) = MAX(CARDINAL) THEN
            session^.state := MustExit;
        END (*IF*);
    END ReturnHex;

(********************************************************************************)

PROCEDURE ReturnValueString (hini: HINI;  session: Session);

    (* Returns a '+', followed by the value of the current INI file entry       *)
    (* (coded as a hexadecimal string), followed by end-of-line.                *)
    (* The session offset and limit affect the returned result: the offset      *)
    (* specifies the starting point (in bytes) relative to the start of the     *)
    (* value string, and the limit is an upper bound on how many bytes to       *)
    (* transfer.  Note that it is possible that this will give a null result.   *)

    (* If the item can't be found in the INI file, the returned result is       *)
    (* instead a line starting with '-'.                                        *)

    VAR S: Socket;  flag: CHAR;
        p: BufferPointer;  itemsize, sendsize: CARDINAL;
        RBP: POINTER TO ARRAY [0..MAX(CARDINAL) DIV 4] OF CHAR;

    BEGIN
        itemsize := 0;
        IF ItemSize (hini, session, itemsize) THEN flag := '+'
        ELSE flag := '-'
        END (*IF*);
        IF itemsize = 0 THEN
            p := NIL;
        ELSE
            ALLOCATE (p, itemsize);
            LoadValue (hini, session, p^, itemsize);
        END (*IF*);

        sendsize := itemsize;
        IF sendsize > session^.limit THEN
            sendsize := session^.limit;
        END (*IF*);
        ALLOCATE (RBP, 2*sendsize+3);

        S := session^.socket;
        RBP^[0] := flag;  RBP^[1] := Nul;
        AppendByteString (p, session^.offset, sendsize, RBP^);
        EVAL (AddEOL(RBP^));
        IF send (S, RBP^, 2*sendsize+3, 0) = MAX(CARDINAL) THEN
            session^.state := MustExit;
        END (*IF*);

        IF p <> NIL THEN
            DEALLOCATE (p, itemsize);
        END (*IF*);
        DEALLOCATE (RBP, 2*sendsize+3);

    END ReturnValueString;

(********************************************************************************)

PROCEDURE StoreValueString (hini: HINI;  session: Session;
                            VAR (*IN*) HexData: ARRAY OF CHAR): BOOLEAN;

    (* Converts a hex string to binary, stores the result as the value of the   *)
    (* current INI file entry, starting at byte offset session^.offset.  Note   *)
    (* that this might lead to an increase in length of the data already        *)
    (* present.                                                                 *)
    (* If the length of the new data is less than session.limit then we assume  *)
    (* that this is the tail of the new value, i.e. the entry is truncated if   *)
    (* necessary so that                                                        *)
    (*     new data length = session.offset + length(new data)                  *)
    (* If on the other hand the amount of new data is greater than or equal to  *)
    (* session.limit, the new data are simply overlaid over the old; this can   *)
    (* lead to an increase in data length but never a truncation.               *)

    VAR success: BOOLEAN;  p: BufferPointer;
        loadsize, buffersize, newamount, storesize, j, k: CARDINAL;
        dummy: ARRAY [0..0] OF CARD8;

    BEGIN
        IF NOT ItemSize (hini, session, loadsize) THEN loadsize := 0 END(*IF*);
        buffersize := loadsize;
        newamount := LENGTH(HexData) DIV 2;
        storesize := session^.offset + newamount;
        IF storesize > buffersize THEN
            buffersize := storesize;
        END (*IF*);

        (* The value of storesize that we've calculated so far is the final     *)
        (* data length based on the assumption that nothing comes after the     *)
        (* new data bytes.  If session^.limit <= newamount then the original   *)
        (* size should dominate if it's bigger.                                 *)

        IF (session^.limit <= newamount) AND (loadsize > storesize) THEN
            storesize := loadsize;
        END (*IF*);

        IF buffersize = 0 THEN
            p := NIL;
        ELSE
            ALLOCATE (p, buffersize);
            IF (session^.offset > 0) OR (loadsize > storesize) THEN
                LoadValue (hini, session, p^, loadsize);
            END (*IF*);
        END (*IF*);

        success := TRUE;
        IF newamount > 0 THEN
            k := 0;
            FOR j := session^.offset TO session^.offset+newamount-1 DO
                success := success AND GetHex2 (HexData, k, p^[j]);
            END (*FOR*);
        END (*IF*);

        IF success THEN
            IF p = NIL THEN
                success := StoreValue (hini, session, dummy, 0);
            ELSE
                success := StoreValue (hini, session, p^, storesize);
                DEALLOCATE (p, buffersize);
            END (*IF*);
        END (*IF*);
        RETURN success;

    END StoreValueString;

(********************************************************************************)

PROCEDURE CopyString (VAR (*IN*) src: ARRAY OF CHAR;  VAR (*OUT*) dst: ARRAY OF CHAR);

    (* String assignment, for a case that Strings.Assign seems to crash on. *)

    VAR k: CARDINAL;

    BEGIN
        k := 0;
        WHILE (k <= HIGH(dst)) AND (k <= HIGH(src)) AND (src[k] <> Nul) DO
            dst[k] := src[k];
            INC (k);
        END (*WHILE*);
        IF k <= HIGH(dst) THEN
            dst[k] := Nul;
        END (*IF*);
    END CopyString;

(********************************************************************************)
(*                     HANDLERS FOR SOME ERROR CONDITIONS                       *)
(********************************************************************************)

PROCEDURE XXX (session: Session;  VAR (*IN*) Command: ARRAY OF CHAR);

    (* Command is not a recognised command. *)

    BEGIN
        Reply2 (session, "-Unknown command ", Command);
    END XXX;

(********************************************************************************)

PROCEDURE NotLoggedIn (session: Session;  VAR (*IN*) Command: ARRAY OF CHAR);

    (* Command is illegal because user is not yet logged in. *)

    BEGIN
        Reply2 (session, "-Not logged in ", Command);
    END NotLoggedIn;

(********************************************************************************)
(*                     HANDLERS FOR THE INDIVIDUAL COMMANDS                     *)
(********************************************************************************)

PROCEDURE SetApp (session: Session;  VAR (*IN*) value: ARRAY OF CHAR);

    (* The A command: set the Application string. *)

    BEGIN
        CopyString (value, session^.Application);
        Reply (session, "+");
    END SetApp;

(********************************************************************************)

PROCEDURE ChangeDir (session: Session;  VAR (*IN*) arg: ARRAY OF CHAR);

    (* The C command: change working directory. *)

    VAR newdir: FilenameString;

    BEGIN
        CopyString (arg, newdir);
        IF SetDirectory (session^.CurrentDir, newdir, session^.AtRoot) THEN
            Reply (session, "+");
        ELSE
            Reply (session, '-');
        END (*IF*);
    END ChangeDir;

(********************************************************************************)

PROCEDURE DeleteCurrent (session: Session;  VAR (*IN*) dummy: ARRAY OF CHAR);

    (* The D command: delete application or key. *)

    VAR hini: HINI;

    BEGIN
        dummy[0] := dummy[0];             (* to avoid a compiler warning. *)
        hini := OpenCurrentINIFile (session);
        IF NOT INIData.INIValid(hini) THEN
            Reply (session, '-');
        ELSE
            IF DeleteKey (hini, session) THEN
                Reply (session, "+");
            ELSE
                Reply (session, '-');
            END (*IF*);
            INIData.CloseINIFile (hini);
        END (*IF*);
    END DeleteCurrent;

(********************************************************************************)

PROCEDURE PostEventSemaphore (session: Session;  VAR (*IN*) semName: ARRAY OF CHAR);

    (* The E command: post on named event semaphore. *)

    VAR hev: OS2.HEV;  count: CARDINAL;

    BEGIN
        hev := 0;
        IF OS2.DosOpenEventSem (semName, hev) = OS2.NO_ERROR THEN
            OS2.DosPostEventSem (hev);
            OS2.DosResetEventSem (hev, count);
            OS2.DosCloseEventSem (hev);
            Reply (session, "+");
        ELSE
            Reply (session, "-");
        END (*IF*);
    END PostEventSemaphore;

(********************************************************************************)

PROCEDURE ChooseFile (session: Session;  VAR (*IN*) filename: ARRAY OF CHAR);

    (* The F command: specify the INI file to work on. *)

    BEGIN
        CopyString (filename, session^.filename);
        Reply (session, "+");
    END ChooseFile;

(********************************************************************************)

PROCEDURE SetKey (session: Session;  VAR (*IN*) value: ARRAY OF CHAR);

    (* The K command: set the Key string. *)

    BEGIN
        CopyString (value, session^.Key);
        Reply (session, "+");
    END SetKey;

(********************************************************************************)

PROCEDURE ListDir (session: Session;  VAR (*IN*) dirname: ARRAY OF CHAR);

    (* The L command: return listing of a directory.  Defaults to current       *)
    (* directory if no directory is specified.                                  *)

    VAR dir, mask: FilenameString;  AtRoot: BOOLEAN;

    BEGIN
        CopyString (dirname, dir);
        MakeFilename (session^.CurrentDir, dir, mask, AtRoot);
        Reply (session, "+");
        IF AtRoot THEN
            ListDrives (session^.socket);
        ELSE
            ListDirectory (session^.socket, mask);
        END (*IF*);
        Reply (session, "");
    END ListDir;

(********************************************************************************)

PROCEDURE MakeDir (session: Session;  VAR (*IN*) newdir: ARRAY OF CHAR);

    (* The M command: make a new directory. *)

    VAR dirname: FilenameString;

    BEGIN
        CopyString (newdir, dirname);
        IF MakeDirectory (session^.CurrentDir, dirname) THEN
            Reply (session, "+");
        ELSE
            Reply (session, '-');
        END (*IF*);
    END MakeDir;

(********************************************************************************)

PROCEDURE Offset (session: Session;  VAR (*IN*) arg: ARRAY OF CHAR);

    (* The O command: specify offset and limit for the V & W commands. *)

    VAR pos: CARDINAL;  value: CARDINAL;

    BEGIN
        pos := 0;
        IF GetHex (arg, pos, value) THEN
            session^.offset := value;
        ELSE
            session^.offset := 0;
        END (*IF*);
        session^.limit := MAX(CARDINAL);
        IF arg[pos] = ',' THEN
            INC (pos);
            IF GetHex (arg, pos, value) THEN
                session^.limit := value;
            END (*IF*);
        END (*IF*);
        Reply (session, '+');
    END Offset;

(********************************************************************************)

PROCEDURE Password (session: Session;  VAR (*IN*) arg: ARRAY OF CHAR);

    (* The P command: log in by supplying a password. *)

    VAR hini: HINI;
        SYSapp: ARRAY [0..4] OF CHAR;
        password: ARRAY [0..31] OF CHAR;

    BEGIN
        SYSapp := "$SYS";
        hini := OpenINIFile ("INIServe.ini");
        IF INIData.INIValid(hini) THEN
            IF NOT INIGetString (hini, SYSapp, "Password", password) THEN
                password := "";
                INIData.INIPutBinary (hini, SYSapp, "Password", password, 0);
            END (*IF*);
            INIData.CloseINIFile (hini);
        ELSE
            password := "";
        END (*IF*);
        IF Strings.Equal (arg, password) THEN
            session^.state := LoggedIn;
            Reply (session, '+');
        ELSE
            Reply (session, '-');
        END (*IF*);
    END Password;

(********************************************************************************)

PROCEDURE Quit (session: Session;  VAR (*IN*) dummy: ARRAY OF CHAR);

    (* The Q command: terminate the editing session. *)

    BEGIN
        dummy[0] := dummy[0];             (* to avoid a compiler warning. *)
        session^.state := MustExit;
        Reply (session, '+');
    END Quit;

(********************************************************************************)

PROCEDURE Relocate (session: Session;  VAR (*IN*) dest: ARRAY OF CHAR);

    (* The R command: move a file. *)

    VAR name: FilenameString;

    BEGIN
        CopyString (dest, name);
        IF MoveFile (session^.CurrentDir, session^.Application, name) THEN
            Reply (session, "+");
        ELSE
            Reply (session, '-');
        END (*IF*);
    END Relocate;

(********************************************************************************)

PROCEDURE Size (session: Session;  VAR (*IN*) dummy: ARRAY OF CHAR);

    (* The S command: return number of bytes for current item. *)

    VAR hini: HINI;
        size: CARDINAL;

    BEGIN
        dummy[0] := dummy[0];             (* to avoid a compiler warning. *)
        hini := OpenCurrentINIFile (session);
        IF NOT INIData.INIValid(hini) THEN
            Reply (session, '-');
        ELSE
            IF ItemSize (hini, session, size) THEN
                ReturnHex (session, size);
            ELSE
                Reply (session, '-');
            END (*IF*);
            INIData.CloseINIFile (hini);
        END (*IF*);
    END Size;

(********************************************************************************)

PROCEDURE TruncatedSize (session: Session;  VAR (*IN*) dummy: ARRAY OF CHAR);

    (* The T command: like S, but modified by offset and limit so that it      *)
    (* returns the number of bytes that V would return.                         *)

    VAR hini: HINI;
        size: CARDINAL;

    BEGIN
        dummy[0] := dummy[0];             (* to avoid a compiler warning. *)
        hini := OpenCurrentINIFile (session);
        IF NOT INIData.INIValid(hini) THEN
            Reply (session, '-');
        ELSE
            IF ItemSize (hini, session, size) THEN
                IF size < session^.offset THEN
                    size := 0;
                ELSE
                    DEC (size, session^.offset);
                END (*IF*);
                IF size > session^.limit THEN
                    size := session^.limit;
                END (*IF*);
                ReturnHex (session, size);
            ELSE
                Reply (session, '-');
            END (*IF*);
            INIData.CloseINIFile (hini);
        END (*IF*);
    END TruncatedSize;

(********************************************************************************)

PROCEDURE Value (session: Session;  VAR (*IN*) dummy: ARRAY OF CHAR);

    (* The V command: return the value of current item. *)

    VAR hini: HINI;

    BEGIN
        dummy[0] := dummy[0];             (* to avoid a compiler warning. *)
        hini := OpenCurrentINIFile (session);
        IF NOT INIData.INIValid(hini) THEN
            Reply (session, '-');
        ELSE
            ReturnValueString (hini, session);
            INIData.CloseINIFile (hini);
        END (*IF*);
    END Value;

(********************************************************************************)

PROCEDURE WriteData (session: Session;  VAR (*IN*) data: ARRAY OF CHAR);

    (* The W command: store new value for current item. *)

    VAR hini: HINI;

    BEGIN
        hini := OpenCurrentINIFile (session);
        IF NOT INIData.INIValid(hini) THEN
            Reply (session, '-');
        ELSE
            IF StoreValueString (hini, session, data) THEN
                Reply (session, '+');
            ELSE
                Reply (session, '-');
            END (*IF*);
            INIData.CloseINIFile (hini);
        END (*IF*);
    END WriteData;

(********************************************************************************)

PROCEDURE XFile (session: Session;  VAR (*IN*) name: ARRAY OF CHAR);

    (* The X command: expunge a file or directory. *)

    VAR thefile: FilenameString;

    BEGIN
        CopyString (name, thefile);
        IF FileDelete (session^.CurrentDir, name) THEN
            Reply (session, "+");
        ELSE
            Reply (session, '-');
        END (*IF*);
    END XFile;

(********************************************************************************)
(*                      THE MAIN COMMAND DISPATCHER                             *)
(********************************************************************************)

TYPE
    HandlerProc = PROCEDURE (Session, VAR (*IN*) ARRAY OF CHAR);
    HandlerArray = ARRAY ['A'..'Z'] OF HandlerProc;

CONST
    HandlerList = HandlerArray {SetApp, XXX, ChangeDir, DeleteCurrent, PostEventSemaphore,
                                ChooseFile, XXX, XXX, XXX, XXX,
                                SetKey, ListDir, MakeDir, XXX, Offset,
                                Password, Quit, Relocate, Size, TruncatedSize,
                                XXX, Value, WriteData, XFile, XXX, XXX};

(********************************************************************************)

PROCEDURE HandleCommand (S: Session;  VAR (*IN*) Command: ARRAY OF CHAR;
                                                     VAR (*OUT*) Quit: BOOLEAN);

    (* Executes one user command.  Returns with Quit=TRUE if the command is one *)
    (* that closes the session, or if the connection is lost.                   *)

    VAR Handler: HandlerProc;

    BEGIN
        IF testing THEN
            STextIO.WriteString (Command);  STextIO.WriteLn;
        END (*IF*);

        (* Watch out for lower case. *)

        Command[0] := CAP(Command[0]);
        IF (Command[0] >= 'A') AND (Command[0] <= 'Z') THEN
            Handler := HandlerList[Command[0]];
        ELSE
            Handler := XXX;
        END (*IF*);

        (* If the user is not yet logged in, only P and Q are legal. *)

        IF (S^.state <> LoggedIn)
                AND (Command[0] <> 'P') AND (Command[0] <> 'Q') THEN
            Handler := NotLoggedIn;
        END (*IF*);

        (* Strip the command letter out of the line. *)

        IF Handler <> XXX THEN
            Strings.Delete (Command, 0, 1);
        END (*IF*);

        (* Call the handler. *);

        Handler (S, Command);
        Quit := S^.state = MustExit;

    END HandleCommand;

(********************************************************************************)

END INICommands.

