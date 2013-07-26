:userdoc.
:title.INIServe documentation
:docprof toc=12.

.***********************************
.*   INTRODUCTION
.***********************************

:h1.Introduction
:p.
INIServe is a server application that allows a remote client to edit
INI file entries on the machine on which INIServe is running.  It is
distributed as freeware. You may distribute it with your own
applications.
This documentation is for version 2.3.
:p.
:hp2.Disclaimer of Warranty:ehp2.

:sl compact.
:li.
:hp8.
This Product is provided "as-is", without warranty of any
kind, either expressed or implied, including, but not limited to,
the implied warranties of merchantability and fitness for a
particular purpose.  The entire risk as to the quality and
performance of the Product is with you.  Should the Product prove
defective, the full cost of repair, servicing, or correction lies
with you.
:ehp8.
:esl.

:p.
The author of INIServe is Peter Moylan, peter@pmoylan.org

:p.
The latest version of INIServe is normally kept at http&colon.&slash.&slash.www.pmoylan.org/ftp/software
.br
Information about other software on this site may be found at
http&colon.&slash.&slash.www.pmoylan.org/pages/os2/software.html.


.***********************************
.*   WHAT IS IT FOR?
.***********************************

:h1 id=whatsitfor.What is it for?

:p.One common way for an OS/2 program to store its
configuration data is in an INI file. This means that you can, in
many cases, alter the program options by editing the program's INI
file. There are, in fact, several INI editors available to let you
do just that.

:p.Normally you wouldn't work directly with the INI file, because
developers generally consider INI data to be internal detail that's
not properly documented for the end user. Most typically these data
are manipulated either via "setup" options in the program itself,
or by a configuration utility supplied by the program's author.
It is sufficient that the author of the software knows what is in
the INI file.

:p.There is one situation where it can be difficult to change a
program's configuration options, and that is where the manager is
trying to look after the software across a network. A way around
the problem is to use a client-server approach to INI editing, and
that's where INIServe comes in. INIServe, which runs on the machine
where the INI file is located, provides the server end of the
connection. All that is needed is a client to run at the other end.

:p.When you received the INIServe package, you probably also received
a demonstration client that is a remote INI file editor. This is
intended only as a demonstration. The long-term aim is that
application-specific clients be written, preferably by the authors
of the software that owns the INI file.

:p.The protocol for the commands accepted by INIServe has been
deliberately kept simple, so that it is easy to write client
software. Any existing "setup" software that manipulates INI
files via operating system API calls should be able to be modified,
with relatively little effort, to instead use INIServe commands
to read and write INI data.

.***********************************
.*   WHAT'S IN AN INI FILE?
.***********************************

:h1 id=INIFileDescription.The contents of an INI file

:p.An INI file is a place where a program can store just about any
data that it likes. Typically it is used to store information that
the program needs to retain from one invocation to the next: screen
location, fonts, user-configurable options, and the like. You
wouldn't want to use it to store a huge database - that could be
inefficient - but an INI file is the ideal place to store those
little bits of information that aren't big enough to deserve a file
of their own.

:p.Internally, the file is a binary file, and I don't plan to tell
you about the precise internal structure. (I believe it's documented somewhere on Hobbes.) The
important thing is that OS/2 provides API calls that let a programmer
read and write INI file entries.

:p.Conceptually, each entry is a triple (application,key,value), where
the application and key are character strings that are usually
human-readable. You can think of this as a two-level hierarchy. The
INI file holds data for a number of different applications; each
application can have a number of keys; and associated with each key
there is a value, which is the thing the program actually wants to read.

:p.Historically, there was probably an intention to have all programs
save their INI data in one huge "user INI file", and in that case the
"application" part of the triple would have identified the program
owning that part of the data. These days we've learnt that concentrating
all the important data in a single central registry is bad design - it
leaves the system vulnerable to damage by a single misbehaving
program - so there's more of a tendency to use a separate INI file for
each program. This being the case, it would be logical to rename the
"application" to something like "section label", since it doesn't
identify an application in many cases; but we continue to call it the
"application" in order to be consistent with the existing documentation.

:p.The "value" part of the entry can be anything at all, depending on the
needs of the programmer who is using the INI file. It can be something
as simple as a one-byte binary value; it could also be a character string,
with or without a null terminating byte; or it could be a complex record
whose internal structure is known only to the programmer.

:p.The meaning of INI file data is usually not documented, because
programmers tend to see it as internal implementation detail. Before
modifying anything in an INI file, make sure that you understand what
the modification will do.

.***********************************
.*   FUNCTIONAL VIEW OF SERVER COMMANDS
.***********************************

:h1 id=funcview.A functional overview of the INIServe commands

:p.The INIServe protocol is intentionally very simple. Every command is
a single letter, followed (without any spaces) by a parameter if
necessary. Some commands have no parameters, so the single letter is
the entire command. Some other commands have a single character string
as a parameter. The parameter for the W command is a string of bytes,
where each byte is expressed as a two-digit hexadecimal number. The
most complicated case is the O command, which has two numeric parameters
separated by a comma.

:p.The command must be terminated by an ASCII carriage return followed
by an ASCII line feed.

:p.The server sends back a response to each command. There are two
kinds of response.
:ul.
:li.If the command failed or was rejected, the response starts with the
'-' character, and this might be followed by a plain-text error message.
:li.If the command was successful, the first character of the response is
the '+' character, and then the data follows if this is the sort of
command that returns data. Most commands don't return anything except the
'+' or '-'; the exceptions are&colon.
:ul.
:li.The S and T commands produce a numeric reply, and this comes as a
hexadecimal number immediately after the '+'.
:li.The V command produces a byte string as the reply, and this is
in the form of a long hexadecimal number, immediately after the '+',
where each two hexadecimal characters represent one byte.
:li.The L command is a special case, producing a multi-line reply. This
is the only case where the reply is more than one line long.
:eul.
:eul.

:p.Every response line is terminated with a carriage return and line feed.

:p.The following pages describe the steps you would go through in a single
INIServe session. For more precise details, refer to the alphabetical
list of commands later in this manual.
:ul compact.
:li.:link reftype=hd refid=loggingin.Logging in:elink.
:li.:link reftype=hd refid=choosingafile.Choosing a file to edit:elink.
:li.:link reftype=hd refid=findappandkey.Finding out what applications and keys are present:elink.
:li.:link reftype=hd refid=checksize.Checking the size of an entry:elink.
:li.:link reftype=hd refid=readingvalue.Reading a value:elink.
:li.:link reftype=hd refid=writingvalue.Adding or modifying an entry:elink.
:li.:link reftype=hd refid=deleting.Deleting an entry:elink.
:li.:link reftype=hd refid=fileops.File operations:elink.
:li.:link reftype=hd refid=misc.Miscellaneous commands:elink.
:li.:link reftype=hd refid=loggingout.Logging out:elink.
:eul.

.***********************************
.*   LOGGING IN
.***********************************

:h2 id=loggingin.Logging in

:p.To start a session, the client must connect to the destination machine
using the TCP port on which INIServe is listening. The default port
number is 3560, which is the port allocated by IANA for the INIServe
protocol. If you want to use a nonstandard port, you can do so by
altering the obvious entry in INIServe.INI.

:p.The server replies with a confirmation line; that is, a line starting
with the '+' character.

:p.The client should then give a password with the 'P' command, for example
:xmp.
       Psecret
:exmp.
:p.If the password is correct, the server replies with another confirmation line,
and the client is then able to issue other commands. The default password is
the empty string, but this can be changed by changing the password in
INIServe.INI.

.***********************************
.*   CHOOSING A FILE
.***********************************

:h2 id=choosingafile.Choosing a file to edit

:p.Three commands are useful here. The L command gives a listing of a
specified directory. (If no directory name is specified, it gives a
listing of the current directory.) The C command is a "change directory" command. Finally,
the F command specifies a file name; this should be the name of an INI
file, of course.

:p.The parameters for these commands can be either an absolute path,
or a path relative to the current directory. Initially the "current
directory" is a pseudo-directory containing the names of all accessible
drives.

:p.If you know the full filename, including drive and directory, for the
file to be worked on, then you can of course give it directly in the
F command. In this case the L and C commands are unnecessary.

.***********************************
.*   READING THE APPLICATIONS AND KEYS
.***********************************

:h2 id=findappandkey.Finding out what applications and keys are present

:p.The A command is for specifying an application, and the K command is
for specifying a key. After you've given these two commands, you are
ready to read the existing value, or write a new value. But what if you
don't know what applications and/or keys exist in the INI file?

:p.If you specify an empty string as the application - that is, if
you use the A command with no parameter - and then use the V command,
the value returned is a hexadecimal string that should be interpreted
as follows&colon.
:ol compact.
:li.Each two hexadecimal characters represents one byte, with the obvious
encoding, so the hexadecimal string can be turned into a byte string.
:li.Considering the byte values as ASCII character codes, the result
can further be interpreted as a character string.
:li.The character string is in fact a sequence of substrings, where each
substring is terminated by a zero byte. (The last substring is
terminated with two zero bytes, one to end the substring and the other
to mark the end of the sequence.) Each of those substrings will turn
out to be the name of one application.
:eol.

:p.In summary, specifying the empty string as the application will give
you a result, when you read the value, which is a list of all applications
in that INI file.

:p.Likewise, you can get a list of all keys, for a given application, by
specifying a real application but setting the key to the empty string
with the K command.

.***********************************
.*   CHECKING THE SIZE OF AN ENTRY
.***********************************

:h2 id=checksize.Checking the size of an entry

:p.The S command asks how many bytes there are in a particular INI file
entry. Use the A and K commands to set the application and key, and
then give the S command (with no parameters). The reply is a + sign
followed by a hexadecimal number.

:p.Depending on how the client software is designed, there might be
some situations where an entry is too big to be read or written in
one piece. The O command tells the server that you want to pick up
the data in limited-size chunks. It has two parameters, an offset
and a limit. The offset says how far from the beginning of an item
we should start. (For example, if the offset is 10 when you issue a
V command, then the V command skips the first 10 bytes of the current
entry.) The second parameter, the limit, specifies a maximum number
of bytes that can be returned by the V command.

:p.Initially, and also after you give an O command with no parameters,
the offset is zero and the limit is the largest possible 32-bit number.
In effect, there is initially no offset or limit.

:p.The T command is like the S command, except that it takes the offset
and limit into account, and tells you the number of bytes that would
actually be returned as a response to the V command.

.***********************************
.*   READING A VALUE
.***********************************

:h2 id=readingvalue.Reading a value

:p.To read an INI file entry, you use the A and K commands to specify the
application and key, and then you give the V command to get the
value. The response to the V command is a + sign followed by a long
string of hexadecimal digits. Each pair of hexadecimal digits gives
the value of one byte.

:p.As noted in the previous subsection, the behaviour of the V command
is affected by the offset and limit specified by the most recent
O command. In particular, the V command will never return more bytes
than specified by the limit, even if there are more bytes than that
in the INI file entry. To get the missing part, if any, you have to
give a new O command with a larger offset.

.***********************************
.*   ADDING OR MODIFYING AN ENTRY
.***********************************

:h2 id=writingvalue.Adding or modifying an entry

:p.The W command is for writing data. First you give the A and K commands
to specify the application and key, then you give the W command. The
letter W should be followed by an even number of hexadecimal digits.
Each pair of digits gives the value of one byte.

:p.If the application/key pair already exists in the INI file, the
new value overwrites the existing entry. Otherwise, a new entry is
created.

:p.If the O command has not been issued, then the length of the new
entry is exactly as long as the number of bytes specified in the W
command. (Even if the old entry was longer.) However, the offset and
limit given by an O command modify the action of the W command.
What happens is that the new value overlays the old value. (If there
wasn't any old value, and you have a nonzero offset, then you can
end up with random rubbish.) The first "offset" bytes of the old
value remain unchanged; then you have the new values supplied with
the W command; and then, possibly, you have more bytes of the old
value.

:p.Whether the "tail" is retained depends on the size of the new
data relative to the current limit. If the number of bytes supplied
with the W command is greater than or equal to the limit, then the
server assumes that this is not the final section of the data, i.e.
it keeps the old data, if any, that stretch more than (offset+N)
bytes from the beginning of the value, where N is the number of
bytes supplied with the W command. If, on the other hand, the
number of bytes supplied with the W command is smaller than the
limit, then the value is truncated at that point.

.***********************************
.*   DELETING AN ENTRY
.***********************************

:h2 id=deleting.Deleting an entry

:p.The D command tells the server to delete the INI file entry
corresponding to the current application and key, as set by
the most recent A and K commands.

:p.If the K command specified an empty string, then all entries,
for all keys associated with the current application, are deleted.

:p.If the A command specified an empty string, then the D
command is illegal.

.***********************************
.*   FILE OPERATIONS
.***********************************

:h2 id=fileops.File operations

:p.The C, F, and L commands have already been mentioned.  The C
command is for changing the current directory, the L command is
for obtaining a directory listing, and the F command is to specify
which INI file you will be operating on.

:p.Sometimes you need to manipulate files on the remote system.
The M command is for creating a new directory, the R command
is for relocating (i.e. moving) a file or directory to a different
place in the file system, and the X command is for deleting a file
or a directory. (Note: deleting a directory will work only if the
directory is empty.) This is admittedly not a complete set of
file operations, but it is sufficient for all known INIServe
applications to date.  More operations might be added in the future,
depending on whether there is any need for them.

.***********************************
.*   MISCELLANEOUS COMMANDS
.***********************************

:h2 id=misc.Miscellaneous commands

:p.The E command allows you to post on an event semaphore on the
remote machine.  Typically, this would be to let the remote
application know that its INI file has been modified.


.***********************************
.*   LOGGING OUT
.***********************************

:h2 id=loggingout.Logging out

:p.When the client has finished working on the INI file(s), it should
send the Q command to terminate the current session.


.***********************************
.***********************************
.*   ALPHABETICAL LIST OF SERVER COMMANDS
.***********************************

:h1 res=002.Alphabetic list of commands

:dl break=none tsize=30.
:dt.      A<string>
:dd.:link reftype=hd refid=Acommand.set application:elink.
:dt.      C<string>
:dd.:link reftype=hd refid=Ccommand.change directory:elink.
:dt.      D
:dd.:link reftype=hd refid=Dcommand.delete the current entry:elink.
:dt.      E<string>
:dd.:link reftype=hd refid=Ecommand.post event semaphore:elink.
:dt.      F<string>
:dd.:link reftype=hd refid=Fcommand.select file to edit:elink.
:dt.      K<string>
:dd.:link reftype=hd refid=Kcommand.set key:elink.
:dt.      L<string>
:dd.:link reftype=hd refid=Lcommand.list directory:elink.
:dt.      M<string>
:dd.:link reftype=hd refid=Mcommand.make directory:elink.
:dt.      O<val>,<val>
:dd.:link reftype=hd refid=Ocommand.set offset and limit (for V and W commands):elink.
:dt.      P<string>
:dd.:link reftype=hd refid=Pcommand.password:elink.
:dt.      Q
:dd.:link reftype=hd refid=Qcommand.quit:elink.
:dt.      R<string>
:dd.:link reftype=hd refid=Rcommand.relocate (move) file or directory:elink.
:dt.      S
:dd.:link reftype=hd refid=Scommand.return size of current item:elink.
:dt.      T
:dd.:link reftype=hd refid=Tcommand.return truncated size of current item:elink.
:dt.      V
:dd.:link reftype=hd refid=Vcommand.return value of current item:elink.
:dt.      W<hexdata>
:dd.:link reftype=hd refid=Wcommand.store new value for current item:elink.
:dt.      X<string>
:dd.:link reftype=hd refid=Xcommand.delete a file or directory:elink.
:edl.

:p.The parameters, if any, for the commands come immediately after the command
letter, with no intervening space. The possible parameter types are as follows.

:dl break=all.
:dt.<string>
:dd.A character string specifying a file name, a password, etc.
:dt.<val>
:dd.A number, expressed in hexadecimal.
:dt.<hexdata>
:dd.A byte sequence of arbitrary length, where each byte is specified by
exactly two hexadecimal digits.
:edl.

:p.The command must be terminated by a carriage return and line feed.

.***********************************
.*   SUBWINDOWS DEFINING DATA TYPES
.***********************************

:h2 hide x=right y=bottom width=80% height=20% group=2 id=stringdef.<string>

A <string> is a sequence of characters in human-readable form. It should not
include the null character (the character with code 0). It is legal to have an
empty string, i.e. a string of zero length.

:h2 hide x=right y=bottom width=80% height=20% group=2 id=valdef.<val>

A <val> is a single unsigned 32-bit integer expressed in hexadecimal. The
value must be in the range 0 to FFFFFFFF.

:h2 hide x=right y=bottom width=80% height=20% group=2 id=hexdatadef.<hexdata>

This is a byte sequence of arbitrary length, where each byte is specified by
exactly two hexadecimal digits.


.***********************************
.*   THE A COMMAND
.***********************************

:h2 id=Acommand.The A command: set Application

:p.:hp2.Form:ehp2.
:p.      A:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      AProg1

:p.:hp2.Discussion:ehp2.
:p.To read or write an INI file entry, you must first specify an application
and key. The usual way to do this is to send an A command, then a K command,
and then the command to read or write the value.

:p.The application name specified in this command remains in force until
the next A command.

:p.:hp2.Special case:ehp2.
:p.If an R command comes after the A command, the string set by the A
command is taken to be a file name rather than an application name.

.***********************************
.*   THE C COMMAND
.***********************************

:h2 id=Ccommand.The C command: Change directory

:p.:hp2.Form:ehp2.
:p.      C:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      C..

:p.:hp2.Discussion:ehp2.
:p.The letter C is followed by a directory name, and this can either be
a complete path (e.g. D&colon.\uvw\xyz) or a name relative to the current
directory (e.g. xyz or ..). You can use this command - multiple times,
if desired - to walk through the directory tree on the target machine
until you reach the directory containing the INI file that you want to
work on.

:p.Before the first C command, the "current directory" is a hypothetical
top-level directory containing all the drives on the system.  Normally,
then, your first C command would be something like "CE:" to select
a drive.

:p.The "current directory" set by this command remains in force until
the next C command, if any. If a C command fails, the current directory
is unchanged.

.***********************************
.*   THE D COMMAND
.***********************************

:h2 id=Dcommand.The D command: Delete the current entry

:p.:hp2.Form:ehp2.
:p.      D

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      D

:p.:hp2.Discussion:ehp2.
:p.The D command has no parameters. It causes the current INI file
entry, as specified by the most recent A and K commands, to be
deleted.

:p.If the current key is the empty string, then all keys and values
for the current application are deleted.

:p.If the current application is the empty string, the command
will fail.

.***********************************
.*   THE E COMMAND
.***********************************

:h2 id=Ecommand.The E command: post event semaphore

:p.:hp2.Form:ehp2.
:p.      E:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the named event semaphore could not be opened
:edl.

:p.:hp2.Example:ehp2.
:p.      E\SEM32\FTPSERVER\UPDATED

:p.:hp2.Discussion:ehp2.
:p.The <string> in this command should be the name of an event
semaphore that exists on the target machine.  The result of
this command is that the semaphore is opened, a "post" operation
followed by a "reset" operation is performed on the semaphore,
and then the semaphore is closed.  For this to have any effect,
there should of course be another program on the target machine
that is waiting for the event to be posted.

.***********************************
.*   THE F COMMAND
.***********************************

:h2 id=Fcommand.The F command: select File to edit

:p.:hp2.Form:ehp2.
:p.      F:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      Fweasel.INI

:p.:hp2.Discussion:ehp2.
:p.This is in effect the "open file" operation that the client must
do before reading or writing INI file entries. The file name after
the F can either be a complete path string, or a name relative to
the directory that was most recently set by the C command.

:p.Physically, this does not open the file. It simply sets the name
of the file to be worked on. For safety, the server opens and
re-closes the file for every operation on the file; this is mildly
inefficient, but it ensures that the INI file remains in a well-defined
state even if the INIServe session is aborted because of something
like a communications failure.

:p.The "current file" set by this command remains in force until
the next F command, if any.


.***********************************
.*   THE K COMMAND
.***********************************

:h2 id=Kcommand.The K command: set Key

:p.:hp2.Form:ehp2.
:p.      K:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      KPassword

:p.:hp2.Discussion:ehp2.
:p.To read or write an INI file entry, you must first specify an application
and key. The usual way to do this is to send an A command, then a K command,
and then the command to read or write the value.

:p.The key name specified in this command remains in force until
the next K command.


.***********************************
.*   THE L COMMAND
.***********************************

:h2 id=Lcommand.The L command: List directory

:p.:hp2.Form:ehp2.
:p.      L:link reftype=hd refid=stringdef.<string>:elink.
:p.The <string> parameter is optional. If an empty string is specified,
you get the listing of the current directory.

:p.:hp2.Reply:ehp2.
:p.This command produces a multi-line reply, where each line is terminated
by a carriage return and line feed.

:p.The first line contains the single character '+'.

:p.Each of the following lines, except for the last, lists one file name.
That is, the current directory is listed with one line per entry. Only
the names are given, not other details such as date and file size.  The
name has a trailing '/' character iff this entry is a directory.

:p.The final line is empty, i.e. it contains nothing except the
terminating carriage return and line feed. This is to mark the end
of the reply.

:p.:hp2.Examples:ehp2.
:p.      L

:p.If the current directory contained two files called "file1" and "mydata",
and a subdirectory called "help", then the response from the server would be
:xmp.
      +<CR><LF>
      ../<CR><LF>
      file1<CR><LF>
      help/<CR><LF>
      mydata<CR><LF>
      <CR><LF>
:exmp.

:p.      L*.exe

:p.This gives a listing of all files in the current directory whose names
end with ".exe".

:p.      LC&colon.\temp\

:p.This gives a listing of all files in the directory C&colon.\temp.

:p.:hp2.Discussion:ehp2.
:p.Note that, at least in the current version, there is no failure response&colon.
the command always succeeds. In the case of an error like selecting a nonexistent
directory, the L command simply returns an empty directory listing.

:p.In parsing a directory string, INIServe considers the characters '/' and
'\' to be equivalent to each other.

.***********************************
.*   THE M COMMAND
.***********************************

:h2 id=Mcommand.The M command: Make directory

:p.:hp2.Form:ehp2.
:p.      M:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      Msubdir

:p.:hp2.Discussion:ehp2.
:p.The letter M is followed by a directory name, and this can either be
a complete path (e.g. D&colon.\uvw\xyz) or a name relative to the current
directory (e.g. xyz). You can use this command to create a new directory
on the target machine. (If the directory already exists, the command
fails and the directory is left unchanged.)

.***********************************
.*   THE O COMMAND
.***********************************

:h2 id=Ocommand.The O command: set Offset and limit

:p.:hp2.Form:ehp2.
:p.      O:link reftype=hd refid=valdef.<val>:elink.,:link reftype=hd refid=valdef.<val>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      OF8,40

:p.This sets the offset to F8 hexadecimal (248 decimal) and the limit to
40 hexadecimal (64 decimal).

:p.:hp2.Discussion:ehp2.
:p.If you deal only with INI file entries that are short, you will never
need the O command. It is there to handle the possibility of entries that
are too large to fit in a client's data buffer, so that you have to work
with substrings of the data.

:p.The offset and limit defined by the O command affect future V and W
commands that read and write data. The offset says how many bytes are
ahead of the chunk of data being dealt with by V and W. The limit is an
upper bound on how many bytes will be read by a V command. The initial
defaults are an offset of zero, and a limit which is the largest possible
32-bit number.

:p.Suppose, for example, that you have to deal with an INI file entry
that is 1024 bytes long, but that buffer size restrictions mean that
you can't deal with more than 128 bytes at a time. In this case you
would set the offset to 0 and the limit to 128, and process the first
128 bytes of the data. Then you would set the offset to 128 (leaving
the limit at 128) to process the next 128 bytes. Next, you would set
the offset to 256 (still with the limit set at 128), and so on.

:p.If an O command is received and only one numeric parameter is
supplied, then the other one reverts to its default value: a zero
offset, or a very large limit, depending on which parameter is missing.
If both parameters are missing, both the offset and limit are set
back to their default values.

:p.The offset and limit specified in this command remain in force until
the next O command.


.***********************************
.*   THE P COMMAND
.***********************************

:h2 id=Pcommand.The P command: supply a Password

:p.:hp2.Form:ehp2.
:p.      P:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the password was accepted
:dt.      -
:dd.if the password was rejected
:edl.

:p.:hp2.Example:ehp2.
:p.      Psecret

:p.:hp2.Discussion:ehp2.
:p.The P command should be the first command sent by the client. Until
the client has supplied a valid password, no commands except P and Q will
be accepted.

:p.When the server is first installed, the initial password is the empty
string, so the correct way to log in is with a P followed directly by a
carriage return and line feed. You should of course change this as soon as
possible. Malicious clients could use INIServe to read or even alter
important system settings. The way to stop this is to use a password that
nobody knows except you.

:p.The password can be up to 32 characters long, and it is case-sensitive.
It can contain any character except the null character.

.***********************************
.*   THE Q COMMAND
.***********************************

:h2 id=Qcommand.The Q command: Quit

:p.:hp2.Form:ehp2.
:p.      Q
:p.(Note that this command has no parameters.)

:p.:hp2.Reply:ehp2.
:p.The reply will always be the single character '+' (followed, of course,
by a carriage return and line feed) to indicate successful completion.
The server will never reject this command, unless of course it is so
badly corrupted by transmission errors that the server does not see the Q.

:p.:hp2.Example:ehp2.
:p.      Q

:p.:hp2.Discussion:ehp2.
:p.This is the "log out" command, and it should be the last command issued
by a client.

.***********************************
.*   THE R COMMAND
.***********************************

:h2 id=Rcommand.The R command: Relocate (move) file or directory

:p.:hp2.Form:ehp2.
:p.      R:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      Asrcfile
:p.      Rdstfile

:p.:hp2.Discussion:ehp2.
:p.A 'move' operation logically requires two operands, to specify the
source and destination file names, but to keep the command syntax
simple the R command specifies only the destination.  The source
parameter is taken to be the string value last specified by an
A command.  (This is an exceptional use of the A command, which
normally specifies an Application string rather than a file name.)

:p.Each of the two file names may be either in the form of
a complete path (e.g. D&colon.\uvw\xyz) or a name relative to the current
directory (e.g. xyz). You can use this command to create a new directory
on the target machine.

.***********************************
.*   THE S COMMAND
.***********************************

:h2 id=Scommand.The S command: return Size of current item

:p.:hp2.Form:ehp2.
:p.      S
:p.(Note that this command has no parameters.)

:p.:hp2.Reply:ehp2.
:p.If the size of the current item cannot be determined (usually because
the INI file doesn't exist) then the reply is the failure code '-'.
Otherwise, the reply is the single character '+' followed by a hexadecimal
number. This number is the length, in bytes, of the INI data specified by
the current application and key, i.e. specified by the most recent A and
K commands.

:p.:hp2.Example:ehp2.
:p.      S
:p.The reply to this would be something like "+2E" (without the quote
marks, and terminated by a carriage return and line feed). Note that the
answer is always given in hexadecimal.

:p.:hp2.Discussion:ehp2.
:p.The size reported by this command is always the full size of the item.
The answer is not affected by any previous O command. (If you want an
answer that does depend on the O command parameters, use the T command.)

:p.If the current application or the current key is the empty string, then
strictly speaking there should be no value to return. In fact the V
command does return an answer in this case - see the description of special
cases for the V command - and the S command reports how many bytes
would be returned.


.***********************************
.*   THE T COMMAND
.***********************************

:h2 id=Tcommand.The T command: return Truncated size of current item

:p.:hp2.Form:ehp2.
:p.      T
:p.(Note that this command has no parameters.)

:p.:hp2.Reply:ehp2.
:p.If the size of the current item cannot be determined (usually because
the INI file doesn't exist) then the reply is the failure code '-'.
Otherwise, the reply is the single character '+' followed by a hexadecimal
number. This number is the length, in bytes, of the data that would be
returned by the V command.

:p.:hp2.Example:ehp2.
:p.      T
:p.The reply to this would be something like "+20" (without the quote
marks, and terminated by a carriage return and line feed). Note that the
answer is always given in hexadecimal.

:p.:hp2.Discussion:ehp2.
:p.This command is almost exactly the same as the S command. The difference
is that the S command is not affected by any previous O command, while
the answer returned for the T command is modified by the offset and limit
set by the most recent O command. The result of the T command tells you
how many data bytes will be returned by the next V command (always assuming,
of course, that you don't issue a new A or K command before the V). The
S command, on the other hand, tells you how many bytes would have been
returned if you hadn't used an O command to limit the size of the transfer.


.***********************************
.*   THE V COMMAND
.***********************************

:h2 id=Vcommand.The V command: return Value of current item

:p.:hp2.Form:ehp2.
:p.      V

:p.:hp2.Reply:ehp2.
:p.If the current item cannot be determined (usually because
the INI file doesn't exist) then the reply is the failure code '-'.
Otherwise, the reply is the single character '+' followed by N bytes of
data, where each byte is specified as a two-digit hexadecimal
number. The total number of characters in the reply is 2N+3; 2N
characters for the N bytes of data, one more for the '+', and two for
the carriage return and line feed that terminate the line.

:p.For the value of N, see the discussion below.

:p.:hp2.Example:ehp2.
:p.      V
:p.If the current item is a four-byte value, then the reply would be
something like
:p.       +00014F37<cr><lf>

:p.:hp2.Discussion:ehp2.
:p.If the O command has not been issued, so that the offset is 0 and
the limit is very large, the result is precisely the current item, however
many bytes that might be. If the O command has been issued, then the value
returned is the value of the current item, truncated as follows.
:ul.
:li.First, the initial "offset" bytes of the value are removed.
:li.If the string resulting from the first operation still has more than
"limit" bytes, then the result is truncated so that only "limit" bytes are
returned. Otherwise, all bytes, apart from the initial ones removed in the
first step, are returned.
:eul.

:p.:hp2.Special cases:ehp2.

:ul.
:li.If the current application name, as set by the A command, is the empty
string, then what is returned is a list of all application names in this INI
file. The result is still encoded in hexadecimal, with two hexadecimal digits
per character, but after decoding this you will have a sequence of
null-terminated character strings, where each character string is the name
of one application. The end of the list is marked by an extra zero byte.
:li.If the current application name is a valid application name, but the
current key name, as set by the K command, is the empty
string, then what is returned is a list of all key names for this application.
The result is still encoded in hexadecimal, with two hexadecimal digits
per character, but after decoding this you will have a sequence of
null-terminated character strings, where each character string is the name
of one key. The end of the list is marked by an extra zero byte.
:eul.

:p.You can use this information to deduce the set of all application/key pairs
in the INI file.

.***********************************
.*   THE W COMMAND
.***********************************

:h2 id=Wcommand.The W command: Write new value for current item

:p.:hp2.Form:ehp2.
:p.      W:link reftype=hd refid=hexdatadef.<hexdata>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      W74657374696E6700

:p.This would set the value of the current item to the null-terminated
character string "testing".

:p.:hp2.Discussion:ehp2.
:p.If the O command has not been issued, so that the current offset is 0
and the current limit is very large, then the byte string specified as
the <hexdata> is stored as the value of the INI file entry for the current
application and key (as set by the most recent A and K commands). This
either creates a new entry or overwrites an existing entry, depending on
whether an old value already existed for that application and key. The
new entry does not have to have the same size as the old entry.

:p.If an offset and limit have been set by the O command, then the new data
supplied by the W command are overlaid over the original data. The first
"offset" bytes remain as before, then the next N bytes (where N is the
number of bytes supplied by the W command) are modified, and subsequent
bytes if any remain unchanged.

:p.Note that N, the number of bytes supplied by the W command, is not
constrained by the current limit. The value of the limit is, however,
used in deciding whether to shorten an existing entry. If N is greater
than or equal to the limit, then later bytes are left unmodified, as
described above. If N is strictly less than the current limit, then
we assume that this is the last "chunk" of this value to be stored,
and the value is truncated at that point. In this case the modified
entry ends up being exactly (offset+N) bytes long.

:p.If N and offset are both zero, the value stored is a byte string
of zero length. This is legal, and it is not equivalent to deleting
the current entry.

.***********************************
.*   THE X COMMAND
.***********************************

:h2 id=Xcommand.The X command: Delete a file or (empty) directory

:p.:hp2.Form:ehp2.
:p.      X:link reftype=hd refid=stringdef.<string>:elink.

:p.:hp2.Reply:ehp2.
:dl compact.
:dt.      +
:dd.if the command was successful
:dt.      -
:dd.if the command failed
:edl.

:p.:hp2.Example:ehp2.
:p.      Xmyfile.tmp

:p.This would delete the file called "myfile.tmp".

:p.:hp2.Discussion:ehp2.
:p.If the parameter is the name of a file, that file will be deleted
if possible. If it is the name of a directory, that directory is
deleted provided that it is empty. If you attempt to delete a
non-empty directory, the command will fail.

:p.Attempting to delete a nonexistent file is legal. Although this
does nothing, it is treated as a command that succeeded.

.***********************************
.*   INSTALLATION
.***********************************

:h1.Installation
:hp2.Installation:ehp2.
:p.
See also :link reftype=hd refid=deinstall.De-installation:elink.

:p.
You should have received this package in the form of a zip file.
To install it, simply unzip the file into a directory of your choice.
(Presumably you've already done this.)  The server is now ready to
run.

:p.
The server itself is the program called INIServe.exe.  You can run it
either by double-clicking on the desktop icon, or by entering the
command "iniserve" in a command-line session.  If you want the server
to be running all the time, then you should probably create a shadow
or program object to go into the startup folder.

:p.The server can be run detached, if desired. In theory it can also
be run from inetd, but I've never tested that option.
:p.
As supplied, the server uses an empty password and listens on port
3560. To change these parameters, make the obvious changes to the
file INIServe.INI. You can use another INI file editor to do this,
but it is also legal to use INIServe to modify its own INI file.

:p.The file source.zip is optional.  If you're not interested in the
source code, you can delete it.

.***********************************
.*   DEINSTALLATION
.***********************************

:h1 id=deinstall.De-installation
:hp2.De-installation:ehp2.
:p.
INIServe does not tamper with CONFIG.SYS or with other system files.
If you decide that you don't want to keep it, simply delete
the directory into which you installed it.

:euserdoc.

