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

MODULE INIServe;

        (********************************************************)
        (*                                                      *)
        (*                  INI file server                     *)
        (*                                                      *)
        (*  Programmer:         P. Moylan                       *)
        (*  Started:            24 May 1998                     *)
        (*  Last edited:        21 July 2015                    *)
        (*  Status:             OK                              *)
        (*                                                      *)
        (********************************************************)

IMPORT OS2, TextIO, ISV;

FROM SYSTEM IMPORT LOC;

FROM LowLevel IMPORT
    (* proc *)  EVAL;

FROM IOChan IMPORT
    (* type *)  ChanId;

FROM Sockets IMPORT
    (* const*)  NotASocket,
    (* type *)  Socket, SockAddr, AddressFamily, SocketType,
    (* proc *)  sock_init, socket, so_cancel, setsockopt, gethostid,
                bind, listen, select, accept, soclose, psock_errno;

FROM Internet IMPORT
    (* const*)  Zero8, INADDR_ANY;

FROM Exceptq IMPORT
    (* proc *)  InstallExceptq, UninstallExceptq;

FROM STextIO IMPORT
    (* proc *)  WriteChar, WriteString, WriteLn;

FROM INIMisc IMPORT
    (* proc *)  OpenINIFile, IPToString, Swap2, Swap4;

FROM INIData IMPORT
    (* type *)  HINI,
    (* proc *)  INIValid, CloseINIFile, INIGet, INIGetString, INIPut;

FROM CtrlC IMPORT
    (* type *)  BreakHandler,
    (* proc *)  SetBreakHandler;

FROM INISession IMPORT
    (* proc *)  SetTimeout, NewSession;

FROM ProgramArgs IMPORT
    (* proc *)  ArgChan, IsArgPresent;

(********************************************************************************)

CONST
    DefaultPort = 3560;
    DefaultTimeout = 900;               (* seconds   *)

VAR
    MainSocket: Socket;
    ServerPort: CARDINAL;
    CalledFromInetd: BOOLEAN;
    ScreenEnabled: BOOLEAN;

(********************************************************************************)

PROCEDURE ["C"] ControlCHandler(): BOOLEAN;

    (* Intercepts a Ctrl/C from the keyboard. *)

    BEGIN
        IF MainSocket <> NotASocket THEN
            so_cancel (MainSocket);
        END (*IF*);
        RETURN TRUE;
    END ControlCHandler;

(********************************************************************************)

PROCEDURE LoadINIData;

    (* Loads setup parameters from "INIServe.ini". *)

    VAR hini: HINI;
        SYSapp: ARRAY [0..4] OF CHAR;

    PROCEDURE GetItem (name: ARRAY OF CHAR;  default: CARDINAL;
                                    VAR (*OUT*) variable: CARDINAL);

        BEGIN
            IF NOT INIGet (hini, SYSapp, name, variable) THEN
                variable := default;
                INIPut (hini, SYSapp, name, variable);
            END (*IF*);
        END GetItem;

    (********************************************************************)

    VAR TimeoutLimit: CARDINAL;
        dummy: ARRAY [0..31] OF CHAR;

    BEGIN
        SYSapp := "$SYS";
        TimeoutLimit := DefaultTimeout;
        hini := OpenINIFile ("INIServe.ini");
        IF INIValid(hini) THEN
            GetItem ("ServerPort", DefaultPort, ServerPort);
            GetItem ("TimeOut", DefaultTimeout, TimeoutLimit);
            IF NOT INIGetString (hini, SYSapp, "Password", dummy) THEN
                dummy := '';
                INIPut (hini, SYSapp, "Password", dummy);
            END (*IF*);
            CloseINIFile (hini);
        END (*IF*);

        SetTimeout (TimeoutLimit);

    END LoadINIData;

(********************************************************************************)

PROCEDURE WriteHostID (ID: ARRAY OF LOC);

    VAR result: ARRAY [0..16] OF CHAR;

    BEGIN
        IPToString (ID, result);
        WriteString (result);
    END WriteHostID;

(********************************************************************************)

PROCEDURE GetParameter (VAR (*OUT*) result: CARDINAL): BOOLEAN;

    (* Picks up an optional program argument from the command line.  If an      *)
    (* argument is present, returns TRUE.                                       *)

    TYPE CharSet = SET OF CHAR;
    CONST Digits = CharSet {'0'..'9'};

    VAR j: CARDINAL;
        args: ChanId;
        ParameterString: ARRAY [0..79] OF CHAR;

    BEGIN
        args := ArgChan();
        IF IsArgPresent() THEN
            TextIO.ReadString (args, ParameterString);
            j := 0;
            WHILE ParameterString[j] = ' ' DO
                INC (j);
            END (*WHILE*);
            result := 0;
            WHILE ParameterString[j] IN Digits DO
                result := 10*result + ORD(ParameterString[j]) - ORD('0');
                INC (j);
            END (*WHILE*);
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END (*IF*);
    END GetParameter;

(************************************************************************)

PROCEDURE WriteCard (val: CARDINAL);

    (* Writes a cardinal to the screen. *)

    BEGIN
        IF val > 9 THEN WriteCard(val DIV 10) END(*IF*);
        WriteChar (CHR(ORD('0') + val MOD 10));
    END WriteCard;

(************************************************************************)

PROCEDURE RunTheServer;

    (*  OPERATING AS A SERVER                                                       *)
    (*     1. (Compulsory) Call "bind" to bind the socket with a local address.     *)
    (*        You can usually afford to specify INADDR_ANY as the machine           *)
    (*        address, but you'd normally bind to a specific port number.           *)
    (*     2. Call "listen" to indicate your willingness to accept connections.     *)
    (*     3. Call "accept", getting a new socket (say ns) from the client.         *)
    (*     4. Use procedures "send" and "recv" to transfer data, using socket ns.   *)
    (*        (Meanwhile, your original socket remains available to accept          *)
    (*        more connections, so you can continue with more "accept" operations   *)
    (*        in parallel with these data operations.  If so, you should of course  *)
    (*        be prepared to run multiple threads.)                                 *)
    (*     5. Use "soclose(ns)" to terminate the session with that particular       *)
    (*        client.                                                               *)
    (*     6. Use "soclose" on your original socket to clean up at the end.         *)

    VAR ns: Socket;  myaddr, client: SockAddr;
        temp: CARDINAL;
        SocketsToTest: ARRAY [0..0] OF Socket;

    BEGIN
        IF sock_init() <> 0 THEN
            IF ScreenEnabled THEN
                WriteString ("No network.");
            END (*IF*);
            RETURN;
        END (*IF*);

        CalledFromInetd := GetParameter (ns);

        IF CalledFromInetd THEN

            IF ScreenEnabled THEN
                WriteString ("INIServe started from inetd, socket ");
                WriteCard (ns);  WriteLn;
                EVAL (SetBreakHandler (ControlCHandler));
            END (*IF*);
            EVAL(NewSession (ns, ScreenEnabled));

        ELSE

            IF ScreenEnabled THEN
                WriteString ("INIServe v");  WriteString (ISV.version);
                WriteString ("  Copyright (C) 1999-2015 Peter Moylan.");
                WriteLn;  WriteHostID (Swap4(gethostid()));  WriteLn;
                EVAL (SetBreakHandler (ControlCHandler));
            END (*IF*);

            MainSocket := socket (AF_INET, SOCK_STREAM, AF_UNSPEC);

            (* Allow reuse of the port we're binding to. *)

            temp := 1;
            setsockopt (MainSocket, 0FFFFH, 4, temp, SIZE(CARDINAL));

            IF ScreenEnabled THEN
                WriteString ("INIServe starting on port ");
                WriteCard (ServerPort);
                WriteString (", socket ");
                WriteCard (MainSocket);
                WriteLn;
                WriteString ("Type Ctrl/C to close down server");  WriteLn;
            END (*IF*);

            (* Now have the socket, bind to our machine. *)

            WITH myaddr DO
                family := AF_INET;
                WITH in_addr DO
                    port := Swap2 (ServerPort);
                    (* Bind to all interfaces. *)
                    addr := INADDR_ANY;
                    zero := Zero8;
                END (*WITH*);
            END (*WITH*);

            IF bind (MainSocket, myaddr, SIZE(myaddr)) THEN
                IF ScreenEnabled THEN
                    WriteString ("Cannot bind to server port.");
                    WriteLn;
                END (*IF*);

            ELSE

                (* Go into listening mode. *)

                EVAL (listen (MainSocket, 1));

                (* Here's the main service loop. *)

                SocketsToTest[0] := MainSocket;
                WHILE select (SocketsToTest, 1, 0, 0, MAX(CARDINAL)) > 0 DO
                    IF SocketsToTest[0] <> NotASocket THEN
                        (*
                        IF ScreenEnabled THEN
                            WriteString ("New connection attempt");
                            WriteLn;
                        END (*IF*);
                        *)
                        temp := SIZE(client);
                        ns := accept (MainSocket, client, temp);
                        IF ns <> NotASocket THEN
                            (*
                            IF ScreenEnabled THEN
                                WriteString ("Starting new session");
                                WriteLn;
                            END (*IF*);
                            *)
                            EVAL(NewSession (ns, ScreenEnabled));
                        END (*IF*);
                    END (*IF*);
                    SocketsToTest[0] := MainSocket;
                END (*WHILE*);

            END (*IF bind*);

            (* Close the sockets. *)

            IF soclose(MainSocket) THEN
                psock_errno ("");
            END (*IF*);

        END (*IF (not) CalledFromInetd *);

    END RunTheServer;

(************************************************************************)

PROCEDURE DetachCheck(): BOOLEAN;

    (* Returns TRUE iff process is not detached.  *)

    VAR pPib: OS2.PPIB;  pTib: OS2.PTIB;

    BEGIN
        OS2.DosGetInfoBlocks (pTib, pPib);
        RETURN pPib^.pib_ultype <> 4;
    END DetachCheck;

(********************************************************************************)
(*                                 MAIN PROGRAM                                 *)
(********************************************************************************)

VAR exRegRec: OS2.EXCEPTIONREGISTRATIONRECORD;

BEGIN
    ScreenEnabled := DetachCheck();
    EVAL(InstallExceptq (exRegRec));
    LoadINIData;
    RunTheServer;
FINALLY
    UninstallExceptq (exRegRec);
END INIServe.

