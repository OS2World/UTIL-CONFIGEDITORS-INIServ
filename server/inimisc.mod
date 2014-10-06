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

IMPLEMENTATION MODULE INIMisc;

        (********************************************************)
        (*                                                      *)
        (*  Miscellaneous stuff that didn't fit anywhere else   *)
        (*                                                      *)
        (*  Programmer:         P. Moylan                       *)
        (*  Started:            17 May 1999                     *)
        (*  Last edited:        30 November 2008                *)
        (*  Status:             OK                              *)
        (*                                                      *)
        (********************************************************)

FROM SYSTEM IMPORT LOC, CARD8, CARD16, CARD32, CAST, ADR;

FROM INIData IMPORT
    (* type *)  HINI;

FROM Conversions IMPORT
    (* type *)  CardinalToString;

IMPORT INIData, Strings, FileSys;

(************************************************************************)

CONST
    Nul = CHR(0);

(************************************************************************)

PROCEDURE SwapIt (VAR (*INOUT*) arg: ARRAY OF LOC);

    (* Reverses the byte order of its argument. *)

    VAR j, top: CARDINAL;  temp: LOC;

    BEGIN
        top := HIGH(arg);
        FOR j := 0 TO top DIV 2 DO
            temp := arg[j];  arg[j] := arg[top-j];  arg[top-j] := temp;
        END (*FOR*);
    END SwapIt;

(************************************************************************)

PROCEDURE Swap2 (val: CARD16): CARD16;

    (* Returns the argument value in byte-reversed order.  This is needed       *)
    (* because network byte order is most significant byte first, whereas our   *)
    (* local host order is least significant byte first.                        *)

    VAR temp: CARD16;

    BEGIN
        temp := val;
        SwapIt (temp);
        RETURN temp;
    END Swap2;

(************************************************************************)

PROCEDURE Swap4 (val: CARD32): CARD32;

    (* Like Swap2, but for a four-byte argument. *)

    VAR temp: CARD32;

    BEGIN
        temp := val;
        SwapIt (temp);
        RETURN temp;
    END Swap4;

(********************************************************************************)

PROCEDURE ConvertCard (number: CARDINAL;  VAR (*OUT*) result: ARRAY OF CHAR;
                                          VAR (*INOUT*) pos: CARDINAL);

    (* Converts number to decimal, left justified starting at result[pos].      *)
    (* On return pos is updated to the next unused array index.                 *)

    VAR j: CARDINAL;  buffer: ARRAY [0..15] OF CHAR;

    BEGIN
        CardinalToString (number, buffer, SIZE(buffer));
        j := 0;
        WHILE buffer[j] = ' ' DO INC(j);  END(*WHILE*);
        WHILE (pos <= HIGH(result)) AND (j < SIZE(buffer)) DO
            result[pos] := buffer[j];  INC(pos);  INC(j);
        END (*WHILE*);
    END ConvertCard;

(********************************************************************************)

PROCEDURE AddEOL (VAR (*INOUT*) buffer: ARRAY OF CHAR): CARDINAL;

    (* Appends a CRLF to the buffer contents, returns the total string length. *)

    CONST CR = CHR(13);  LF = CHR(10);

    VAR length: CARDINAL;

    BEGIN
        length := Strings.Length (buffer);
        buffer[length] := CR;  INC(length);
        buffer[length] := LF;  INC(length);
        RETURN length;
    END AddEOL;

(********************************************************************************)

PROCEDURE IPToString (IP: ARRAY OF LOC;  VAR (*OUT*) result: ARRAY OF CHAR);

    (* Converts a four-byte IP address (in network byte order) to a             *)
    (* human-readable form.  There must be at least 17 character positions      *)
    (* available in the result array.                                           *)

    VAR j, position: CARDINAL;

    BEGIN
        result[0] := '[';  position := 1;
        FOR j := 0 TO 2 DO
            ConvertCard (CAST(CARD8,IP[j]), result, position);
            result[position] := '.';  INC(position);
        END (*FOR*);
        ConvertCard (CAST(CARD8,IP[3]), result, position);
        result[position] := ']';  INC(position);
        IF position <= HIGH(result) THEN
            result[position] := Nul;
        END (*IF*);
    END IPToString;

(********************************************************************************)
(*                           INI FILE HANDLING                                  *)
(********************************************************************************)

PROCEDURE OpenINIFile (filename: ARRAY OF CHAR): HINI;

    (* Opens an INI file. *)

    VAR pos: CARDINAL;  found: BOOLEAN;
        extension: ARRAY [0..127] OF CHAR;

    BEGIN
        Strings.FindPrev (".", filename, LENGTH(filename), found, pos);
        IF found THEN
            Strings.Extract (filename, pos+1, LENGTH(filename)-pos, extension);
            Strings.Capitalize (extension);
        ELSE
            extension := "";
        END (*IF*);
        IF FileSys.Exists (filename) THEN
            RETURN INIData.OpenINIFile (filename, Strings.Equal(extension, "TNI"));
        ELSE
            RETURN INIData.CreateINIFile (filename, Strings.Equal(extension, "TNI"));
        END (*IF*);
    END OpenINIFile;

(********************************************************************************)

PROCEDURE INIGet (hini: HINI;  name1, name2: ARRAY OF CHAR;
                                     VAR (*OUT*) variable: ARRAY OF LOC): BOOLEAN;

    (* Retrieves the value of a variable from the INI file.  Returns FALSE if   *)
    (* the variable was not found.                                              *)

    VAR size: CARDINAL;

    BEGIN
        RETURN INIData.INIGet (hini, name1, name2, variable);
    END INIGet;

(********************************************************************************)

PROCEDURE INIGetString (hini: HINI;  name1, name2: ARRAY OF CHAR;
                                    VAR (*OUT*) variable: ARRAY OF CHAR): BOOLEAN;

    (* Like INIGet, but we accept any size data that will fit in the variable,  *)
    (* and we add a Nul terminator in the case of a size mismatch.              *)

    VAR size: CARDINAL;

    BEGIN
        RETURN INIData.INIGetString (hini, name1, name2, variable);
    END INIGetString;

(********************************************************************************)

PROCEDURE INIPut (hini: HINI;  name1, name2: ARRAY OF CHAR;  variable: ARRAY OF LOC);

    (* Writes data to the INI file. *)

    BEGIN
        INIData.INIPut (hini, name1, name2, variable);
    END INIPut;

(********************************************************************************)

END INIMisc.

