(**************************************************************************)
(*                                                                        *)
(*  INIServe server for remote access to INI/TNI files.                   *)
(*  Copyright (C) 2015   Peter Moylan                                     *)
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

IMPLEMENTATION MODULE INISession;

        (********************************************************)
        (*                                                      *)
        (*        Session handler for the INIServe server       *)
        (*                                                      *)
        (*  Programmer:         P. Moylan                       *)
        (*  Started:            24 May 1998                     *)
        (*  Last edited:        21 July 2015                    *)
        (*  Status:             Working                         *)
        (*                                                      *)
        (********************************************************)

IMPORT Strings, OS2;

FROM SYSTEM IMPORT
    (* type *)  ADDRESS,
    (* proc *)  ADR;

FROM Storage IMPORT
    (* proc *)  ALLOCATE, DEALLOCATE;

FROM LowLevel IMPORT
    (* proc *)  EVAL;

FROM Sockets IMPORT
    (* const*)  AF_INET,
    (* type *)  Socket,
    (* proc *)  send, recv, soclose, so_cancel;

FROM INIMisc IMPORT
    (* proc *)  AddEOL;

FROM Semaphores IMPORT
    (* type *)  Semaphore,
    (* proc *)  CreateSemaphore, DestroySemaphore, Signal;

FROM Timer IMPORT
    (* proc *)  TimedWait, Sleep;

FROM TaskControl IMPORT
    (* proc *)  CreateTask1, TaskExit;

FROM STextIO IMPORT
    (* proc *)  WriteChar, WriteString, WriteLn;

FROM LowLevel IMPORT
    (* proc *)  Copy;

IMPORT INICommands;

(************************************************************************)

CONST
    Nul = CHR(0);

TYPE
    (* Data shared by the session handler and the timeout checker. *)

    SessionDataPointer = POINTER TO
                           RECORD
                               socket: Socket;
                               watchdog: Semaphore;
                               alive, TimedOut: BOOLEAN;
                           END (*RECORD*);

VAR
    (* Timeout delay, in milliseconds. *)

    MaxTime: CARDINAL;

    (* Flag to say the process has a screen window. *)

    ScreenEnabled: BOOLEAN;

(************************************************************************)

PROCEDURE SetTimeout (seconds: CARDINAL);

    (* Specifies how long a session can be idle before it is forcibly   *)
    (* closed.                                                          *)

    BEGIN
        IF seconds > MAX(CARDINAL) DIV 1000 THEN
            MaxTime := MAX(CARDINAL);
        ELSE
            MaxTime := 1000*seconds;
        END (*IF*);
    END SetTimeout;

(************************************************************************)

PROCEDURE TimeoutChecker (arg: ADDRESS);

    (* A new instance of this task is created for each client session.  *)
    (* It kills the corresponding SessionHandler task if more than      *)
    (* MaxTime milliseconds have passed since the last Signal() on the  *)
    (* session's KeepAlive semaphore.                                   *)

    VAR p: SessionDataPointer;

    BEGIN
        p := arg;
        REPEAT
            TimedWait (p^.watchdog, MaxTime, p^.TimedOut);
        UNTIL p^.TimedOut;
        IF p^.alive THEN
            so_cancel (p^.socket);
        END (*IF*);

        (* Wait for the socket to be closed. *)

        WHILE p^.alive DO
            Sleep (500);
        END (*WHILE*);
        DestroySemaphore (p^.watchdog);
        DISPOSE (p);

    END TimeoutChecker;

(************************************************************************)
(*                          RECEIVING A COMMAND                         *)
(************************************************************************)

TYPE CharArrayPointer = POINTER TO ARRAY [0..MAX(CARDINAL) DIV 4] OF CHAR;

CONST ChunkSize = 128;

(************************************************************************)

PROCEDURE GetChunk (S: Socket;
                      VAR (*OUT*) text: ARRAY OF CHAR;
                        VAR (*OUT*) EOL: BOOLEAN): CARDINAL;

    (* Returns a partial line from the input stream.  Returns if        *)
    (* ChunkSize characters have been received, or on end of input, or  *)
    (* if a line feed has been received.  Carriage returns and line     *)
    (* feeds are discarded, but a line feed terminates the fetch and    *)
    (* sets the EOL flag.  The function result is the number of         *)
    (* characters returned.                                             *)

    CONST CR = CHR(13);  LF = CHR(10);

    VAR length: CARDINAL;

    BEGIN
        length := recv (S, text, ChunkSize, 0);
        EOL := length = MAX(CARDINAL);
        IF EOL THEN
            length := 0;
        END (*IF*);

        (* Command should end with CR LF, but for simplicity we'll      *)
        (* ignore the CR.  Beware of the case where the LF or CR LF     *)
        (* comes at the beginning of the final chunk.                   *)

        IF (length > 0) AND (text[length-1] = LF) THEN
            DEC (length);  EOL := TRUE;
        END (*IF*);
        IF (length > 0) AND (text[length-1] = CR) THEN
            DEC (length);
        END (*IF*);

        (* Add a string terminator.  (Not actually necessary.)  *)

        IF length < ChunkSize THEN
            text[length] := Nul;
        END (*IF*);

        RETURN length;

    END GetChunk;

(************************************************************************)

PROCEDURE BuildCommand (S: Socket;
                          VAR (*OUT*) result: CharArrayPointer): CARDINAL;

    (* Reads one command from the input stream, returns its length.  It *)
    (* is the caller's responsibility to discard the result after use.  *)

    TYPE Chunk = POINTER TO
                    RECORD
                        next: Chunk;
                        size: CARDINAL;
                        text: ARRAY [0..ChunkSize-1] OF CHAR;
                    END (*RECORD*);

    VAR length, pos: CARDINAL;
        head, this, tail: Chunk;
        EOL: BOOLEAN;

    BEGIN
        length := 0;
        head := NIL;  tail := NIL;

        (* Since we have no limit on the length of the command line, we *)
        (* initially collect the line in chunks.                        *)

        REPEAT
            NEW (this);
            this^.next := NIL;
            this^.size := GetChunk (S, this^.text, EOL);
            IF this^.size = 0 THEN
                DISPOSE (this);
            ELSE
                INC (length, this^.size);
                IF tail = NIL THEN
                    head := this;
                ELSE
                    tail^.next := this;
                END (*IF*);
                tail := this;
            END (*IF*);
        UNTIL EOL;

        (* Now that we know the total length, combine the chunks. *)

        IF length = 0 THEN
            result := NIL;
        ELSE
            INC (length);
            ALLOCATE (result, length);
            pos := 0;
            WHILE head <> NIL DO
                Copy (ADR(head^.text), ADR(result^[pos]), head^.size);
                INC (pos, head^.size);
                this := head;
                head := this^.next;
                DISPOSE (this);
            END (*WHILE*);
            result^[length-1] := Nul;
        END (*IF*);

        RETURN length;

    END BuildCommand;

(************************************************************************)

PROCEDURE SessionHandler (arg: ADDRESS);

    (* The task that handles a client session, i.e. this is where all the real  *)
    (* work is done.  There might be several instances of this task running,    *)
    (* one for each session that is still open.                                 *)

    VAR S: Socket;
        Response: ARRAY [0..15] OF CHAR;
        SDP: SessionDataPointer;
        sess: INICommands.Session;
        CmdPtr: CharArrayPointer;
        size: CARDINAL;
        Quit: BOOLEAN;

    BEGIN                   (* Body of SessionHandler *)

        OS2.DosError (OS2.FERR_DISABLEHARDERR);              (* disable hard error popups *)

        (* Fill in the SessionDataPointer^ information. *)

        SDP := arg;
        WITH SDP^ DO
            S := socket;
            CreateSemaphore (watchdog, 0);
            alive := TRUE;  TimedOut := FALSE;
        END (*WITH*);

        (* Create the session information structure. *)

        sess := INICommands.OpenSession(S);

        (* Create an instance of the TimeoutChecker task. *)

        EVAL (CreateTask1 (TimeoutChecker, 3, "INIServe timeout", SDP));

        (* Send the "welcome" message. *)

        Strings.Assign ("+", Response);
        size := AddEOL (Response);
        Quit := send (S, Response, size, 0) = MAX(CARDINAL);

        (* Here's the main command processing loop.  We leave it when the client  *)
        (* issues a QUIT command, or when socket communications are lost, or      *)
        (* when we get a timeout on the watchdog semaphore.                       *)

        LOOP
            IF Quit THEN EXIT(*LOOP*) END(*IF*);
            size := BuildCommand (S, CmdPtr);
            IF size > 0 THEN
                Signal (SDP^.watchdog);
                (*
                IF ScreenEnabled THEN
                    WriteString ("Command: ");
                    WriteString (CmdPtr^);
                    WriteLn;
                END (*IF*);
                *)
                INICommands.HandleCommand (sess, CmdPtr^, Quit);
                DEALLOCATE (CmdPtr, size);
            ELSE
                EXIT (*LOOP*);
            END (*IF*);
        END (*LOOP*);

        INICommands.CloseSession (sess);
        SDP^.alive := FALSE;
        soclose (S);
        TaskExit;

    EXCEPT
        soclose(S);
        TaskExit;

    END SessionHandler;

(********************************************************************************)

PROCEDURE NewSession (S: Socket;  NotDetached: BOOLEAN): BOOLEAN;

    (* Starts and runs a client session.  The session runs in a separate        *)
    (* thread; this procedure returns after starting the session, it does not   *)
    (* wait until the session is over.                                          *)

    VAR SDP: SessionDataPointer;

    BEGIN
        ScreenEnabled := NotDetached;
        NEW (SDP);
        SDP^.socket := S;
        RETURN CreateTask1 (SessionHandler, 3, "INIServe session", SDP);
    END NewSession;

(********************************************************************************)
(*                            MODULE INITIALISATION                             *)
(********************************************************************************)

BEGIN
    MaxTime := MAX(CARDINAL);
    ScreenEnabled := TRUE;
END INISession.

