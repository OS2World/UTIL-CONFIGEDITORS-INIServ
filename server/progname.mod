IMPLEMENTATION MODULE ProgName;

    (****************************************************************)
    (*                                                              *)
    (*       A module that lets low-level modules obtain            *)
    (*       application-specific information.  We achieve          *)
    (*       this by putting this module in a directory             *)
    (*       reserved for application-specific source files,        *)
    (*       while the library modules still live at                *)
    (*       "library" level of the source structure.               *)
    (*                                                              *)
    (*    Last edited:    6 January 2013                            *)
    (*    Status:         OK                                        *)
    (*                                                              *)
    (****************************************************************)


IMPORT Strings;

IMPORT ISV;

(************************************************************************)

PROCEDURE GetProgramName (VAR (*OUT*) name: ARRAY OF CHAR);

    (* Returns a name and version string. *)

    BEGIN
        Strings.Assign ("INIServe ", name);
        Strings.Append (ISV.version, name);
    END GetProgramName;

(************************************************************************)

END ProgName.

