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

IMPLEMENTATION MODULE INIFiles;

        (********************************************************)
        (*                                                      *)
        (*          File operations for INIServe                *)
        (*                                                      *)
        (*  Programmer:         P. Moylan                       *)
        (*  Started:            30 May 1998                     *)
        (*  Last edited:        21 July 2015                    *)
        (*  Status:             OK except that FileDelete       *)
        (*                            is untested               *)
        (*                                                      *)
        (********************************************************)


FROM SYSTEM IMPORT
    (* type *)  CARD16, CARD32,
    (* proc *)  CAST, ADR;

IMPORT OS2, Strings, FileSys;

FROM Sockets IMPORT
    (* type *)  Socket,
    (* proc *)  send;

(************************************************************************)

CONST Nul = CHR(0);

TYPE
    FileName = ARRAY [0..OS2.CCHMAXPATHCOMP-1] OF CHAR;
    FileAttribute = (readonly,hidden,system,b3,directory,archive);
    FileAttr = SET OF FileAttribute;
    DirectoryEntry =
           RECORD
               dirHandle : CARD32;    (* directory handle *)
               attr      : FileAttr;  (* file attributes *)
               timePkd   : CARD16;    (* packed time in DOS format *)
               datePkd   : CARD16;    (* packed date in DOS format *)
               size      : CARD32;    (* file length *)
               name      : FileName;  (* file name   *)
           END (*RECORD*);

(************************************************************************)
(*                        DIRECTORY SEARCHES                            *)
(************************************************************************)

PROCEDURE ConvertFindResult (VAR (*IN*) FindBuffer: OS2.FILEFINDBUF3;
                             VAR (*OUT*) D: DirectoryEntry);

    (* Copies the result of a directory lookup to the format we're using. *)

    BEGIN
        D.attr    := CAST (FileAttr, FindBuffer.attrFile);
        D.timePkd := FindBuffer.ftimeLastWrite;
        D.datePkd := FindBuffer.fdateLastWrite;
        D.size    := FindBuffer.cbFile;
        Strings.Assign (FindBuffer.achName, D.name);
    END ConvertFindResult;

(************************************************************************)

PROCEDURE FirstDirEntry (mask: ARRAY OF CHAR;  Subdirectory: BOOLEAN;
                                  VAR (*OUT*) D: DirectoryEntry): BOOLEAN;

    (* Gets the first directory entry satisfying the conditions:        *)
    (*  (a) if Subdirectory is FALSE, we want the first entry that      *)
    (*      matches "mask".                                             *)
    (*  (b) if Subdirectory is TRUE, we want the first directory that   *)
    (*      matches "mask".                                             *)
    (* In either case "mask" is a filename specification that may       *)
    (* include wildcards.                                               *)

    CONST ResultBufLen = SIZE(OS2.FILEFINDBUF3);

    VAR FindBuffer: OS2.FILEFINDBUF3;
        attrib, FindCount: CARDINAL;
        rc: OS2.APIRET;

    BEGIN
        OS2.DosError (OS2.FERR_DISABLEHARDERR);
        D.dirHandle := OS2.HDIR_CREATE;
        FindCount := 1;
        IF Subdirectory THEN
            attrib := 1037H;
        ELSE
            attrib := 037H;
        END (*IF*);
        rc := OS2.DosFindFirst (mask, D.dirHandle, attrib,
                                ADR(FindBuffer), ResultBufLen,
                                FindCount, OS2.FIL_STANDARD);
        ConvertFindResult (FindBuffer, D);
        RETURN rc = OS2.NO_ERROR;
    END FirstDirEntry;

(************************************************************************)

PROCEDURE NextDirEntry (VAR (*INOUT*) D: DirectoryEntry): BOOLEAN;

    (* Read the next directory entry satisfying the search criteria     *)
    (* specified by the FirstDirEntry call.                             *)

    CONST ResultBufLen = SIZE(OS2.FILEFINDBUF3);

    VAR FindBuffer: OS2.FILEFINDBUF3;
        FindCount: CARDINAL;
        rc: OS2.APIRET;

    BEGIN
        OS2.DosError (OS2.FERR_DISABLEHARDERR);
        FindCount := 1;
        rc := OS2.DosFindNext(D.dirHandle, ADR(FindBuffer),
                              ResultBufLen, FindCount);
        ConvertFindResult (FindBuffer, D);
        RETURN rc = OS2.NO_ERROR;
    END NextDirEntry;

(************************************************************************)

PROCEDURE DirSearchDone (VAR (*INOUT*) D: DirectoryEntry);

    (* Close the directory that D represents. *)

    BEGIN
        OS2.DosFindClose (D.dirHandle);
    END DirSearchDone;

(************************************************************************)
(*                   SENDING BACK A DIRECTORY LISTING                   *)
(************************************************************************)

PROCEDURE ListDrives (S: Socket);

    (* Sends a list of drive names to socket S.  We send one name per line. *)

    TYPE ReplyLine = ARRAY [0..4] OF CHAR;

    CONST StdReply = ReplyLine {'A', ':', '/', CHR(13), CHR(10)};

    VAR disknum, flags: CARDINAL;
        j: [0..25];
        Line: ReplyLine;

    BEGIN
        OS2.DosError (OS2.FERR_DISABLEHARDERR);
        OS2.DosQueryCurrentDisk (disknum, flags);
        Line := StdReply;
        FOR j := 0 TO 25 DO
            IF ODD(flags) THEN
                send (S, Line, 5, 0);
            END (*IF*);
            flags := flags DIV 2;  INC (Line[0]);
        END (*FOR*);
    END ListDrives;

(************************************************************************)

PROCEDURE ListDirectory (S: Socket;  Mask: ARRAY OF CHAR);

    (* Sends a list of all files matching mask to socket S.  (If Mask   *)
    (* ends with a '\' or '/', we list all files in the directory whose *)
    (* name is in Mask.)  We send one name per line.                    *)

    VAR D: DirectoryEntry;  success: BOOLEAN;
        CRLF: ARRAY [0..1] OF CHAR;
        Slash: ARRAY [0..0] OF CHAR;
        length: CARDINAL;
        InfoBuf: OS2.FSALLOCATE;

    (********************************************************************)

    PROCEDURE SendOneEntry;

        BEGIN
            send (S, D.name, LENGTH(D.name), 0);
            IF directory IN D.attr THEN
                send (S, Slash, 1, 0);
            END (*IF*);
            send (S, CRLF, 2, 0);
        END SendOneEntry;

    (********************************************************************)

    BEGIN
        OS2.DosError (OS2.FERR_DISABLEHARDERR);
        CRLF[0] := CHR(13);  CRLF[1] := CHR(10);
        Slash[0] := '/';
        length := Strings.Length (Mask);
        IF (length = 2) AND (Mask[1] = ':') THEN

            (* Special case: we're being asked to confirm the existence *)
            (* of a drive.                                              *)

            IF OS2.DosQueryFSInfo (ORD(CAP(Mask[0])) - ORD('A') + 1,
                           1, ADR(InfoBuf), SIZE(InfoBuf)) = 0 THEN
                Strings.Assign (Mask, D.name);
                D.attr := FileAttr{directory};
                SendOneEntry;
            END (*IF*);

        ELSE
            IF (length > 0) AND ((Mask[length-1] = '\') OR (Mask[length-1] = '/')) THEN
                Strings.Append ("*", Mask);
                D.name := "..";  D.attr := FileAttr{directory};  SendOneEntry;
            END (*IF*);
            success := FirstDirEntry (Mask, FALSE, D);
            WHILE success DO
                IF NOT Strings.Equal (D.name, ".")
                             AND NOT Strings.Equal (D.name, "..") THEN
                    SendOneEntry;
                END (*IF*);
                success := NextDirEntry (D);
            END (*WHILE*);
            DirSearchDone (D);
        END (*IF*);
    END ListDirectory;

(************************************************************************)

PROCEDURE MakeFilename (VAR (*IN*) CurrentDir: FilenameString;
                        VAR (*IN*) newdir: ARRAY OF CHAR;
                        VAR (*OUT*) result: FilenameString;
                        VAR (*OUT*) AtRoot: BOOLEAN);

    (* If newdir is an absolute path, it replaces result.  If it's      *)
    (* a relative path, result is the concatenation of CurrentDir and   *)
    (* newdir.  In either case, AtRoot is set TRUE iff this puts us at  *)
    (* the root of the directory tree.                                  *)
    (* Assumption: CurrentDir ends with a '\'.                          *)

    VAR pos: CARDINAL;
        AddSlash: BOOLEAN;
        ch: CHAR;

    BEGIN
        (* Remove any trailing '/' or '\', but remember it was there    *)
        (* so that we can later put it back.                            *)

        pos := Strings.Length (newdir);
        AddSlash := pos > 0;
        IF AddSlash THEN
            DEC (pos);
            ch := newdir[pos];
            AddSlash := (ch = '/') OR (ch = '\');
            IF AddSlash THEN
                newdir[pos] := Nul;
            END (*IF*);
        END (*IF*);

        result := CurrentDir;

        (* Construct the new directory name.  There are several cases   *)
        (* to consider, depending on things like whether we're working  *)
        (* with an absolute or relative path.                           *)

        IF newdir[0] = Nul THEN

            (* Nothing to do. *)

        ELSIF (CurrentDir[0] = Nul) OR (newdir[1] = ':') THEN

            Strings.Assign (newdir, result);

        ELSIF (newdir[0] = '\') OR (newdir[0] = '/') THEN

            result[2] := Nul;
            Strings.Append (newdir, result);

        ELSIF (newdir[0] = '.') AND (newdir[1] = Nul) THEN

            AddSlash := FALSE;

        ELSIF (newdir[0] = '.') AND (newdir[1] = '.') AND
                                     (newdir[2] = Nul) THEN

            (* Move up a level. *)

            pos := LENGTH (result) - 1;
            IF (result[pos] = '\') OR (result[pos] = '/') THEN
                DEC (pos);
            END (*IF*);
            WHILE (pos > 0) AND (result[pos] <> '\')
                                 AND (result[pos] <> '/') DO
                DEC (pos);
            END (*WHILE*);
            result[pos] := Nul;
            AddSlash := TRUE;

        ELSE

            Strings.Append (newdir, result);

        END (*IF*);

        IF AddSlash THEN
            Strings.Append ('\', result);
        END (*IF*);
        AtRoot := result[1] = Nul;

    END MakeFilename;

(************************************************************************)

PROCEDURE FileIsDirectory (filename: ARRAY OF CHAR): BOOLEAN;

    (* Returns TRUE iff this is the name of a directory. *)

    VAR D: DirectoryEntry;  found: BOOLEAN;

    BEGIN
        found := FirstDirEntry (filename, FALSE, D) AND (directory IN D.attr);
        DirSearchDone (D);
        RETURN found;
    END FileIsDirectory;

(************************************************************************)

PROCEDURE SetDirectory (VAR (*INOUT*) CurrentDir: FilenameString;
                        VAR (*IN*) newdir: ARRAY OF CHAR;
                        VAR (*OUT*) AtRoot: BOOLEAN): BOOLEAN;

    (* If newdir is an absolute path, it replaces CurrentDir.  If it's  *)
    (* a relative path, it's used to update CurrentDir.  In either      *)
    (* case, AtRoot is set TRUE iff this puts us at the root of the     *)
    (* directory tree.                                                  *)

    VAR NewDirectory: FilenameString;
        D: DirectoryEntry;
        pos: CARDINAL;

    BEGIN
        MakeFilename (CurrentDir, newdir, NewDirectory, AtRoot);

        (* Strip any trailing '\', in order to do the directory check. *)

        pos := LENGTH (NewDirectory);
        IF pos > 0 THEN
            DEC (pos);
            IF (NewDirectory[pos] = '\') OR (NewDirectory[pos] = '/') THEN
                NewDirectory[pos] := Nul;
            END (*IF*);
        END (*IF*);

        (* Now check that the new name is a valid directory name. *)

        IF (NewDirectory[0] = Nul) OR
                 ((NewDirectory[1] = ':') AND (NewDirectory[2] = Nul)) THEN
            CurrentDir := NewDirectory;
            Strings.Append ('\', CurrentDir);
            RETURN TRUE;

        ELSIF (FirstDirEntry (NewDirectory, TRUE, D))
                         AND (directory IN D.attr) THEN
            CurrentDir := NewDirectory;
            Strings.Append ('\', CurrentDir);
            DirSearchDone (D);
            RETURN TRUE;
        ELSE
            DirSearchDone (D);
            RETURN FALSE;
        END (*IF*);

    END SetDirectory;

(************************************************************************)

PROCEDURE MakeDirectory (VAR (*IN*) CurrentDir: FilenameString;
                         VAR (*IN*) newdir: ARRAY OF CHAR): BOOLEAN;

    (* Creates a new directory.  The newdir parameter can specify       *)
    (* either an absolute path or a relative path.                      *)

    VAR NewDirectory: FilenameString;

    BEGIN
        NewDirectory := CurrentDir;

        (* Construct the new directory name.  There are several cases   *)
        (* to consider, depending on things like whether we're working  *)
        (* with an absolute or relative path.                           *)

        IF newdir[0] = Nul THEN

            RETURN FALSE;

        ELSIF (CurrentDir[0] = Nul) OR (newdir[1] = ':') THEN

            Strings.Assign (newdir, NewDirectory);

        ELSIF (newdir[0] = '\') OR (newdir[0] = '/') THEN

            NewDirectory[2] := Nul;
            Strings.Append (newdir, NewDirectory);

        ELSE

            Strings.Append (newdir, NewDirectory);

        END (*IF*);

        RETURN FileSys.CreateDirectory(NewDirectory);

    END MakeDirectory;

(************************************************************************)

PROCEDURE AbsFilename (VAR (*IN*) CurrentDir: FilenameString;
                        VAR (*INOUT*) name: ARRAY OF CHAR);

    (* If name is an absolute path, it is left unchanged.  If it's      *)
    (* a relative path, it is changes to the concatenation of           *)
    (* CurrentDir and name.  Assumption: CurrentDir ends with a '\'.    *)

    VAR result: FilenameString;  dummy: BOOLEAN;

    BEGIN
        MakeFilename (CurrentDir, name, result, dummy);
        Strings.Assign (result, name);
    END AbsFilename;

(************************************************************************)

PROCEDURE MoveFile (VAR (*IN*) CurrentDir: FilenameString;
                         VAR (*IN*) src, dst: ARRAY OF CHAR): BOOLEAN;

    (* Moves a file or directory.  The src and dst parameters can       *)
    (* specify either an absolute path or a relative path.              *)

    BEGIN
        AbsFilename (CurrentDir, src);
        AbsFilename (CurrentDir, dst);
        RETURN OS2.DosMove (src, dst) = 0;
    END MoveFile;

(************************************************************************)

PROCEDURE FileDelete (VAR (*IN*) CurrentDir: FilenameString;
                         VAR (*IN*) name: ARRAY OF CHAR): BOOLEAN;

    (* Deletes a file or directory.  The name parameter can specify     *)
    (* either an absolute path or a relative path.  Trying to delete a  *)
    (* nonexistent file is OK.  Trying to delete a nonempty directory   *)
    (* is not OK, and will give a FALSE result.                         *)

    BEGIN
        AbsFilename (CurrentDir, name);
        IF FileIsDirectory(name) THEN
            RETURN OS2.DosDeleteDir(name) = 0;
        ELSE
            RETURN OS2.DosDelete(name) = 0;
        END (*IF*);
    END FileDelete;

(************************************************************************)

END INIFiles.

