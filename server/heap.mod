IMPLEMENTATION MODULE Heap;

        (************************************************************)
        (*                                                          *)
        (*      Heap storage, with a way to log the amount used     *)
        (*                                                          *)
        (*    Started:        22 July 2012                          *)
        (*    Last edited:    26 December 2013                      *)
        (*    Status:         OK                                    *)
        (*                                                          *)
        (************************************************************)


IMPORT SYSTEM, Storage, Strings;

FROM TaskControl IMPORT
    (* type *)  Lock,
    (* proc *)  CreateLock, DestroyLock, Obtain, Release, CreateTask;

FROM Semaphores IMPORT
    (* type *)  Semaphore,
    (* proc *)  CreateSemaphore, DestroySemaphore, Wait, Signal;

FROM Timer IMPORT
    (* proc *)  TimedWait;

FROM Inet2Misc IMPORT
    (* proc *)  ConvertCard;

FROM TransLog IMPORT
    (* type *)  TransactionLogID,
    (* proc *)  LogTransaction;

(************************************************************************)

CONST
    Nul = CHR(0);

TYPE
    TrackMessage = ARRAY [0..15] OF CHAR;

    Track = POINTER TO TrackRecord;
    TrackRecord = RECORD
                      next: Track;
                      count: INTEGER;
                      msg: TrackMessage;
                  END (*RECORD*);

VAR
    (* Variables needed for logging memory usage. *)

    LogID: TransactionLogID;
    MemCount: CARDINAL;
    MemCountLock: Lock;

    (* List of subsidiary tracks to log. *)

    TrackList: Track;

    (* Shutdown, etc., bookkeeping. *)

    LogTaskRunning: BOOLEAN;
    ShutdownRequested: Semaphore;
    TaskDone: Semaphore;

(************************************************************************)
(*                     ALLOCATION AND DEALLOCATION                      *)
(************************************************************************)

PROCEDURE ALLOCATE (VAR (*OUT*) addr: SYSTEM.ADDRESS; amount: CARDINAL);

    (* Allocates storage for a variable of size amount and assigns the  *)
    (* address of this variable to addr. If there is insufficient       *)
    (* unallocated storage to do this, the value NIL is assigned to addr.*)

    BEGIN
        Storage.ALLOCATE (addr, amount);
        IF addr <> NIL THEN
            Obtain (MemCountLock);
            INC (MemCount, amount);
            Release (MemCountLock);
        END (*IF*);
    END ALLOCATE;

(************************************************************************)

PROCEDURE DEALLOCATE (VAR (*INOUT*) addr: SYSTEM.ADDRESS; amount: CARDINAL);

    (* Deallocates amount locations allocated by ALLOCATE for the       *)
    (* storage of the variable addressed by addr and assigns the value  *)
    (* NIL to addr.                                                     *)

    BEGIN
        Storage.DEALLOCATE (addr, amount);
        IF amount > 0 THEN
            Obtain (MemCountLock);
            DEC (MemCount, amount);
            Release (MemCountLock);
        END (*IF*);
    END DEALLOCATE;

(************************************************************************)

PROCEDURE GetHeapCount(): CARDINAL;

    (* Returns the current total allocated (by this module) bytes. *)

    VAR count: CARDINAL;

    BEGIN
        Obtain (MemCountLock);
        count := MemCount;
        Release (MemCountLock);
        RETURN count;
    END GetHeapCount;

(************************************************************************)

PROCEDURE SayHeapCount (ID: TransactionLogID;  label: ARRAY OF CHAR);

    (* Debugging: display current heap count. *)

    VAR count, pos: CARDINAL;
        message: ARRAY [0..63] OF CHAR;

    BEGIN
        Strings.Assign (label, message);
        Strings.Append (": heap count = ", message);
        pos := Strings.Length(message);
        count := GetHeapCount();
        ConvertCard (count, message, pos);
        message[pos] := Nul;
        Strings.Append (" bytes", message);
        LogTransaction (ID, message);
    END SayHeapCount;

(************************************************************************)
(*                        PROVISION FOR LOGGING                         *)
(************************************************************************)

PROCEDURE PutLogMessage (ID: TransactionLogID;  msg: ARRAY OF CHAR;
                                                count: INTEGER);

    (* Puts a usage message to the log. *)

    VAR pos: CARDINAL;
        message: ARRAY [0..63] OF CHAR;

    BEGIN
        Strings.Assign (msg, message);
        Strings.Append (": ", message);
        IF count < 0 THEN
            Strings.Append ("-", message);
            count := -count;
        END (*IF*);
        pos := Strings.Length(message);
        ConvertCard (count, message, pos);
        message[pos] := Nul;
        Strings.Append (" bytes", message);
        LogTransaction (ID, message);
    END PutLogMessage;

(************************************************************************)

PROCEDURE HeapLogTask;

    (* A separate thread that logs the memory use counts. *)

    CONST seconds = 10;

    VAR TimedOut: BOOLEAN;
        T: Track;

    BEGIN
        REPEAT
            Obtain (MemCountLock);
            PutLogMessage (LogID, "Heap used", MemCount);
            T := TrackList;
            WHILE T <> NIL DO
                PutLogMessage (LogID, T^.msg, T^.count);
                T := T^.next;
            END (*WHILE*);
            Release (MemCountLock);
            TimedWait (ShutdownRequested, 1000*seconds, TimedOut);
        UNTIL NOT TimedOut;
        Signal (TaskDone);
    END HeapLogTask;

(************************************************************************)

PROCEDURE EnableHeapLogging (ID: TransactionLogID);

    (* Activates the task that puts out use counts to a log file. *)

    BEGIN
        IF NOT LogTaskRunning THEN
            LogID := ID;
            CreateTask (HeapLogTask, 2, "Heap log");
            LogTaskRunning := TRUE;
        END (*IF*);
    END EnableHeapLogging;

(************************************************************************)

PROCEDURE StopHeapLogging;

    (* Stops the heap-logging task, if it was running. *)

    BEGIN
        IF LogTaskRunning THEN
            Signal (ShutdownRequested);
            Wait (TaskDone);
            LogTaskRunning := FALSE;
        END (*IF*);
    END StopHeapLogging;

(************************************************************************)
(*                      TRACKING A SUBSET OF USE                        *)
(************************************************************************)

PROCEDURE StartTracking (message: ARRAY OF CHAR): Track;

    (* Introduces a new user of memory tracking. *)

    VAR T: Track;

    BEGIN
        NEW (T);
        Obtain (MemCountLock);
        T^.next := TrackList;
        T^.count := 0;
        Strings.Assign (message, T^.msg);
        TrackList := T;
        Release (MemCountLock);
        RETURN T;
    END StartTracking;

(************************************************************************)

PROCEDURE TrackUpdate (T: Track;  amount: INTEGER);

    (* Updates the count for this particular track. *)

    BEGIN
        IF T <> NIL THEN
            Obtain (MemCountLock);
            INC (T^.count, amount);
            Release (MemCountLock);
        END (*IF*);
    END TrackUpdate;

(************************************************************************)
(*                             INITIALISATION                           *)
(************************************************************************)

BEGIN
    LogTaskRunning := FALSE;
    MemCount := 0;
    TrackList := NIL;
    CreateLock (MemCountLock);
    CreateSemaphore (ShutdownRequested, 0);
    CreateSemaphore (TaskDone, 0);
FINALLY
    StopHeapLogging;
    DestroySemaphore (TaskDone);
    DestroySemaphore (ShutdownRequested);
    DestroyLock (MemCountLock);
END Heap.

