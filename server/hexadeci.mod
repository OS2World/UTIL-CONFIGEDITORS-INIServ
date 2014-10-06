(**************************************************************************)
(*                                                                        *)
(*  INIServe client.                                                      *)
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

IMPLEMENTATION MODULE Hexadecimal;

        (********************************************************)
        (*                                                      *)
        (*          Binary/Hexadecimal conversions              *)
        (*                                                      *)
        (*  Programmer:         P. Moylan                       *)
        (*  Started:            11 June 1998                    *)
        (*  Last edited:        23 March 1998                   *)
        (*  Status:             OK                              *)
        (*                                                      *)
        (********************************************************)

FROM SYSTEM IMPORT
    (* type *)  CARD8;


TYPE CharSet = SET OF CHAR;

CONST DecimalDigits = CharSet {'0'..'9'};
      HexDigits = CharSet {'0'..'9', 'A'..'F', 'a'..'f'};

(************************************************************************)
(*                        BINARY TO HEXADECIMAL                         *)
(************************************************************************)

PROCEDURE HexCode (val: CARD8): CHAR;

    (* Returns a hexadecimal code for a one-digit number. *)

    BEGIN
        IF val < 10 THEN
            RETURN CHR (ORD('0') + val);
        ELSE
            RETURN CHR (ORD('A') + val - 10);
        END (*IF*);
    END HexCode;

(************************************************************************)

PROCEDURE PutHex2 (val: CARD8;  VAR (*INOUT*) buffer: ARRAY OF CHAR;
                               VAR (*INOUT*) pos: CARDINAL);

    (* Stores a two-digit hexadecimal number at buffer[pos],    *)
    (* and updates pos.                                         *)

    BEGIN
        buffer[pos] := HexCode (val DIV 16);  INC (pos);
        buffer[pos] := HexCode (val MOD 16);  INC (pos);
    END PutHex2;

(************************************************************************)

PROCEDURE PutHex (val: CARDINAL;  VAR (*INOUT*) buffer: ARRAY OF CHAR;
                                  VAR (*INOUT*) pos: CARDINAL);

    (* Stores a hexadecimal number at buffer[pos], and updates pos.     *)

    BEGIN
        IF val > 15 THEN
            PutHex (val DIV 16, buffer, pos);
        END (*IF*);
        buffer[pos] := HexCode (val MOD 16);  INC (pos);
    END PutHex;

(************************************************************************)
(*                         HEXADECIMAL TO BINARY                        *)
(************************************************************************)

PROCEDURE SkipSpaces (VAR (*INOUT*) buffer: ARRAY OF CHAR;
                      VAR (*INOUT*) pos: CARDINAL);

    (* Moves pos past space characters. *)

    BEGIN
        WHILE (pos <= HIGH(buffer)) AND (buffer[pos] = ' ') DO
            INC (pos);
        END (*WHILE*);
    END SkipSpaces;

(************************************************************************)

PROCEDURE Hex1 (ch: CHAR): CARDINAL;

    (* Converts a one-digit hexadecimal number to numeric.  It is       *)
    (* assumed that the caller has already checked that the character   *)
    (* is a legal hexadecimal digit.                                    *)

    BEGIN
        IF ch IN DecimalDigits THEN
            RETURN ORD(ch) - ORD('0');
        ELSE
            RETURN ORD(CAP(ch)) - ORD('A') + 10;
        END (*IF*);
    END Hex1;

(************************************************************************)

PROCEDURE GetHex (VAR (*INOUT*) buffer: ARRAY OF CHAR;
                  VAR (*INOUT*) pos: CARDINAL;
                  VAR (*OUT*) val: CARDINAL): BOOLEAN;

    (* Reads a hexadecimal number at buffer[pos], possibly preceded by  *)
    (* space characters, and updates pos.  Returns FALSE if no          *)
    (* hexadecimal character was found.                                 *)

    BEGIN
        SkipSpaces (buffer, pos);
        IF (pos > HIGH(buffer)) OR NOT (buffer[pos] IN HexDigits) THEN
            RETURN FALSE;
        END (*IF*);
        val := 0;
        REPEAT
            val := 16*val + Hex1(buffer[pos]);
            INC (pos);
        UNTIL (pos > HIGH(buffer)) OR NOT (buffer[pos] IN HexDigits);
        RETURN TRUE;
    END GetHex;

(************************************************************************)

PROCEDURE GetHex2 (VAR (*INOUT*) buffer: ARRAY OF CHAR;
                  VAR (*INOUT*) pos: CARDINAL;
                  VAR (*OUT*) val: CARD8): BOOLEAN;

    (* Like GetHex, but reads at most two digits.  *)

    VAR result: CARDINAL;

    BEGIN
        SkipSpaces (buffer, pos);
        IF (pos > HIGH(buffer)) OR NOT (buffer[pos] IN HexDigits) THEN
            RETURN FALSE;
        END (*IF*);
        result := Hex1(buffer[pos]);  INC(pos);
        IF (pos <= HIGH(buffer)) AND (buffer[pos] IN HexDigits) THEN
            result := 16*result + Hex1(buffer[pos]);
            INC (pos);
        END (*IF*);
        val := result;
        RETURN TRUE;
    END GetHex2;

(************************************************************************)

END Hexadecimal.

