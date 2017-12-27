/* Build script for INIServe.  Rexx used because some operations need it. */

'del client.zip 2> nul'
'del server.zip 2> nul'
'del iniser*.zip 2> nul'

/* Compile the server program.  The client is a DrDialog program,       */
/* so has to be built (by dropping the RES file onto the "ResToExe"     */
/* icon in the DrDialog desktop folder) independently of this script.   */

'xc =p iniserve.prj'
'\apps\lxlite\lxlite *.exe'
ver = version()
say "Version "ver
call bldlvl ver

/* Create the sym and xqs files. */
/* (Comment out the next three lines if you don't have Perl. */

'call PerlEnv.cmd'
perl 'D:\Apps\scripts\makexqs.pl' iniserve.map
say "iniserve.sym and iniserve.xqs should now exist"

/* Zip up the 'server' package */

cd doc
'ipfc -i iniserve.ipf'
cd ..
rem call seticon
mkdir temp
cd temp
mkdir source
mkdir doc
'copy ..\doc\iniserve.ipf doc'
'copy ..\doc\changes.doc doc'
'Imports ..\INIServe | zip -j -u source\source.zip -@'
'copy ..\doc\iniserve.inf'
'copy ..\iniserve.prj'
'copy ..\iniserve.exe'
'copy ..\iniserve.cmd'
'copy ..\iniserve.map'
'copy ..\iniserve.sym'
'copy ..\iniserve.xqs'
'zip -r ..\server.zip .'
'del doc\* /n'
rmdir doc
'del source\* /n'
rmdir source
'del * /n'

/* Zip up the 'client' package */

mkdir source
'copy ..\res\inied1.res source'
'copy ..\inied1.exe'
'copy ..\inied1.ico'
'zip -r ..\client.zip .'
'del source\* /n'
rmdir source
'del * /n'

/* Make the final zip file */

cd ..
rmdir temp
'copy D:\Dev1\general\doc\gpl.txt'
'zip iniser'ver'.zip README file_id.diz server.zip client.zip gpl.txt makezip.cmd'
'zip iniser'ver'.zip doc\BUILDING*'
del server.zip
del client.zip
del gpl.txt


