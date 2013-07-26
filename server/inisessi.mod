IMPLEMENTATION MODULE INISession;

        (********************************************************)
        (*                                                      *)
        (*        Session handler for the INIServe server       *)
        (*                                                      *)
        (*  Programmer:         P. Moylan                       *)
        (*  Started:            24 May 1998                     *)
        (*  Last edited:        17 May 1999                     *)
        (*  Status:             Working                         *)
        (*                                                      *)
        (********************************************************)

IMPORT Strings, OS2;

FROM SYSTEM IMPORT
    (* type *)  ADDRESS;

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

IMPORT INICommands;

(************************************************************************)

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

PROCEDURE SessionHandler (arg: ADDRESS);

    (* The task that handles a client session, i.e. this is where all the real  *)
    (* work is done.  There might be several instances of this task running,    *)
    (* one for each session that is still open.                                 *)

    CONST CR = CHR(13);  LF = CHR(10);

    VAR S: Socket;
        CmdBuffer: ARRAY [0..1023] OF CHAR;

        (* Temporary buffer for BuildCommand. *)

        TmpBuffer: ARRAY [0..127] OF CHAR;
        tmppos, tmplength: CARDINAL;  ch: CHAR;

    (********************************************************************)

    PROCEDURE BuildCommand(): BOOLEAN;

        VAR length: CARDINAL;
            IACreceived, IgnoreNext: BOOLEAN;

        BEGIN
            length := 0;
            IACreceived := FALSE;  IgnoreNext := FALSE;
            LOOP
                IF tmppos >= tmplength THEN
                    tmplength := recv (S, TmpBuffer, SIZE(TmpBuffer), 0);
                    IF (tmplength = MAX(CARDINAL)) OR (tmplength = 0) THEN
                        RETURN FALSE;
                    END (*IF*);
                    tmppos := 0;
                END (*IF*);
                ch := TmpBuffer[tmppos];  INC(tmppos);

                (* This next section skips over Telnet control codes (which we  *)
                (* don't really want to know about).  A Telnet control code is  *)
                (* two or three bytes long, where the first byte is CHR(255).   *)

                IF IgnoreNext THEN
                    IgnoreNext := FALSE;
                ELSIF IACreceived THEN
                    IACreceived := FALSE;
                    IF ORD(ch) = 255 THEN
                        IF length < SIZE(CmdBuffer) THEN
                            CmdBuffer[length] := ch;  INC(length);
                        END (*IF*);
                    ELSIF ORD(ch) > 250 THEN
                        IgnoreNext := TRUE;
                    END (*IF*);
                ELSIF ORD(ch) = 255 THEN
                    IACreceived := TRUE;

                (* Command should end with CR LF, but for simplicity we'll      *)
                (* ignore the CR.                                               *)

                ELSIF ch = CR THEN  (* Do nothing *)
                ELSIF ch = LF THEN
                    IF length < SIZE(CmdBuffer) THEN
                        CmdBuffer[length] := CHR(0);
                    END (*IF*);
                    RETURN TRUE;
                ELSIF length < SIZE(CmdBuffer) THEN
                    CmdBuffer[length] := ch;  INC(length);
                END (*IF*);

            END (*LOOP*);

        END BuildCommand;

    (********************************************************************)

    VAR SDP: SessionDataPointer;
        sess: INICommands.Session;
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

        CreateTask1 (TimeoutChecker, 3, "INIServe timeout", SDP);

        (* Send the "welcome" message. *)

        Strings.Assign ("+", CmdBuffer);
        size := AddEOL (CmdBuffer);
        Quit := send (S, CmdBuffer, size, 0) = MAX(CARDINAL);

        (* Here's the main command processing loop.  We leave it when the client  *)
        (* issues a QUIT command, or when socket communications are lost, or      *)
        (* when we get a timeout on the watchdog semaphore.                       *)

        tmppos := 0;  tmplength := 0;
        LOOP
            IF Quit THEN EXIT(*LOOP*) END(*IF*);
            IF BuildCommand() THEN
                Signal (SDP^.watchdog);
                INICommands.HandleCommand (sess, CmdBuffer, Quit);
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

PROCEDURE NewSession (S: Socket);

    (* Starts and runs a client session.  The session runs in a separate        *)
    (* thread; this procedure returns after starting the session, it does not   *)
    (* wait until the session is over.                                          *)

    VAR SDP: SessionDataPointer;

    BEGIN
        NEW (SDP);
        SDP^.socket := S;
        CreateTask1 (SessionHandler, 3, "INIServe session", SDP);
    END NewSession;

(********************************************************************************)
(*                            MODULE INITIALISATION                             *)
(********************************************************************************)

BEGIN
    MaxTime := MAX(CARDINAL);
END INISession.

