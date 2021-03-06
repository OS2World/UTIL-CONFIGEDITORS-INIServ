� �� 0�  d   MainDialogue� LocalButton� RemoteButton�  � SetupButton�  � Status�  �   EditINIFilef  AppListg  KeyListe   �   h  	ValueList�   i  Message�   �   ,  EditDialogue-  . AppBox0  / KeyBox1	 ValBox2  3  �  EditOneString� DataBox�  �  OpenDialogue� FileList� 
OpenButton�  X  SetupDialogueY  Z  \  [  a  `  _  ��� 0�  Reformat�PARSE ARG dat
len = LENGTH(dat)
HexString = C2XS(dat)
IF len<16 THEN
     DO j=len+1 TO 16
      HexString = HexString||'   '
     END
HexString = HexString||'  '
DO WHILE len>0
   ch = LEFT(dat,1)
   len = len-1
   dat = RIGHT(dat,len)
   IF ch = '0'X THEN HexString = HexString||'.'
   ELSE HexString = HexString||ch 
END
RETURN HexStringINIDeleteKey�PARSE ARG a,k
IF RemoteFlag THEN
  DO
    CALL ExecCmd("A"||a)
    CALL ExecCmd("K"||k)
    CALL ExecCmd("D")
  END
ELSE CALL INIdel INIFile, a, k
INIDeleteApp�PARSE ARG a
IF RemoteFlag THEN
  DO
    CALL ExecCmd("A"||a)
    CALL ExecCmd("K")
    CALL ExecCmd("D")
  END
ELSE CALL INIDel INIFile, a, ''
INISetValue�PARSE ARG a,k,v
IF RemoteFlag THEN
  DO
    CALL ExecCmd("A"||a)
    CALL ExecCmd("K"||k)
    CALL ExecCmd("W"||C2X(v))
  END
ELSE
  DO
    IF v = "" THEN v = '0'X
    CALL INIput INIFile, a, k, v
  ENDINIGetValue�PARSE ARG App,Key
IF RemoteFlag THEN
  DO
    CALL ExecCmd("A"||App)
    CALL ExecCmd("K"||Key)
    CALL SockSend CommandSocket, 'V'||'0D0A'X
    RETURN GetByteString()
  END
RETURN INIget(INIFile, App, Key) 
INIGetApps�PARSE ARG stem
IF RemoteFlag THEN
  DO
    INTERPRET stem'0 = 0'
    IF ExecCmd("A") THEN
      CALL ReceiveNameList stem
  END
ELSE DO
  list = INIGet(INIFile, '', '')
  j = 0
  DO WHILE list \= ''
      PARSE VAR list name '0'X list
      IF name <> '' THEN
        DO
          j = j+1
          INTERPRET stem'j = name'
        END
  END
  INTERPRET stem'0 = j'
END

INIGetKeys�PARSE ARG a,stem
IF RemoteFlag THEN
  DO
    INTERPRET stem'0 = 0'
    IF ExecCmd("A"||a) & ExecCmd("K") THEN
            CALL ReceiveNameList stem
  END
ELSE DO
  list = INIGet(INIFile, app, '')
  j = 0
  DO WHILE list \= ''
      PARSE VAR list name '0'X list
      IF name <> '' THEN
        DO
          j = j+1
          INTERPRET stem'j = name'
        END
  END
  INTERPRET stem'0 = j'
END
ReadINIValue�PARSE ARG App,Key
IF RemoteFlag THEN
  DO
    CALL ExecCmd("A"||App)
    CALL ExecCmd("K"||Key)
    CALL SockSend CommandSocket, 'V'||'0D0A'X
    RETURN GetByteString()
  END
ELSE DO
  RETURN INIGet(INIFile, App, Key)
END
ExecCmdOPARSE ARG str
RETURN (SockSend(CommandSocket, str||'0D0A'X) \= -1) & OKReply()GetByteStringpline = ReceiveLine()
IF LEFT(line,1) \= '+' THEN RETURN ''
line = RIGHT(line,LENGTH(line)-1)
RETURN X2C(line)ReceiveNameList�PARSE ARG stem'.'
CALL SockSend CommandSocket, 'V'||'0D0A'X
list = GetByteString()
j = 0
DO WHILE list \= ''
  PARSE VAR list name '0'X list
  IF name <> '' THEN
    DO
      j = j+1
      INTERPRET stem'.j = name'
    END
END
INTERPRET stem'.0 = j'
ReceiveLine�line = ''
DO FOREVER
  len = LENGTH(RB)
  IF len = 0 THEN
    DO
      NullResponseCount = 0
      DO WHILE len = 0
        len = SockRecv(CommandSocket, 'RB', 256)
        IF len = 0 THEN
          DO
            NullResponseCount = NullResponseCount+1
            IF NullResponseCount > 20 THEN len = -1
          END
      END /*do-while*/
      IF len = -1 THEN RETURN ''
    END /* if len=0 */
  j0 = POS('0A'X, RB)
  IF j0 = 0 THEN
    DO
      line = STRIP(line||RB, 'T', '0D'X)
      RB = ''
    END
  ELSE
    DO
      line = STRIP(line||LEFT(RB,j0-1), 'T', '0D'X)
      RB = RIGHT(RB,len-j0)
      RETURN line
    END
END /* do forever */
FillList�CALL FileList.Delete
IF ExecCmd("L") THEN
  DO UNTIL name = ''
    name = ReceiveLine()
    IF name \= '' THEN CALL FileList.Add name, 'L'
  END
OKReply"RETURN LEFT(ReceiveLine(),1) = '+'ConnectToServer�	IF CommandSocket \= -1 THEN CALL SockSoClose(CommandSocket)
CommandSocket = SockSocket("AF_INET", "SOCK_STREAM", "IPPROTO_TCP")
IF CommandSocket = -1 THEN
  DO
    CALL Status.Text "Can't create socket"
    RETURN 0
  END
IF DATATYPE(LEFT(ServerAddress,1))='NUM' THEN host.addr = ServerAddress
ELSE
  DO
    CALL Status.Text "Looking up name"
    IF \SockGetHostByName(ServerAddress,'host.') THEN
      DO
        CALL SockSoClose(CommandSocket)
        CALL Status.Text "Unknown host"
        DROP host.
        RETURN 0
      END
  END
CALL Status.Text "Attempting to connect"
target.!family = 'AF_INET'
target.!port = ServerPort
target.!addr = host.addr
DROP host.
rc = SockConnect(CommandSocket,"target.!")
IF rc = -1 THEN
  DO
    CALL SockSoClose(CommandSocket)
    CALL Status.Text "Failed to connect"
    RETURN 0
  END
IF \OKReply() THEN
  DO
    CALL SockSoClose(CommandSocket)
    CALL Status.Text "Server rejected us"
    RETURN 0
  END
IF \ExecCmd("P"||Password) THEN
  DO
    CALL ExecCmd "Q"
    CALL SockSoClose(CommandSocket)
    CALL Status.Text "Wrong password"
    RETURN 0
  END
CALL Status.Text "Connected"
RETURN 1
C2XS�PARSE ARG temp
len0 = LENGTH(temp)
val = ''
DO WHILE len0>0
   val = val||C2X(LEFT(temp,1))||' '
   len0 = len0-1
   temp = RIGHT(temp,len0)
END
RETURN val	LoadValue�App = AppList.Item(AppNumber)
Key = KeyList.Item(KeyNumber)
CALL ValueList.Delete
tail = ReadINIValue(App, Key)
IF tail \= 'ERROR:' THEN
   DO
      k = LENGTH(tail)
      DO WHILE k>0
         IF k>16 THEN
            DO
               part = LEFT(tail,16)
               k = k-16
               tail = RIGHT(tail,k)
            END
         ELSE
            DO
               part = tail
               tail = ''
               k = 0
            END
         CALL ValueList.Add Reformat(part), 'L'
      END
      CALL ValueList.Select(1)
   ENDLoadKeys�App = AppList.Item(AppNumber)
CALL ValueList.Delete
CALL KeyList.Delete
CALL INIGetKeys App, 'Keys.'
IF Keys.0 > 0 THEN
   DO
      DO j=1 TO Keys.0
         CALL KeyList.Add Keys.j, 'A'
      END
      CALL KeyList.Select(1)
   END
LoadApps�CALL ValueList.Delete
CALL KeyList.Delete
CALL AppList.Delete
call INIGetApps 'Apps.'
CALL Message.Text Apps.0" apps"
IF Apps.0 > 0 THEN
   DO
      DO j=1 TO Apps.0
         CALL AppList.Add Apps.j, 'A'
      END
      CALL AppList.Select(1)
   END�� �d 0�  �  �  ��         
 � �  �eP j 2 d ��	         � " , 	 ���        . �  , 
 �5��        P  �;  (  �S��        �  �
 
 ( 
 ����        �  �; 
 ( 
 ����         � �   g 
 ����         �    1  ����INI editor    Local          9.WarpSans     Remote          9.WarpSans     GO .      &   20.Helvetica Bold                     Setup          9.WarpSans     Exit          9.WarpSans               9.WarpSans               9.WarpSans     ���d 0�  �d Exit7IF RemoteFlag THEN CALL ExecCmd "Q"
CALL SockDropFuncsInit�CALL RxFuncAdd SysLoadFuncs, rexxutil, sysloadfuncs
CALL SysLoadFuncs
CALL RxFuncAdd "SockLoadFuncs","rxSock","SockLoadFuncs"
CALL SockLoadFuncs
OurINI = "INIEd1.INI" 
RemoteFlag = INIGet(OurINI,"iedr","Remote")
IF RemoteFlag = 1 THEN
  DO
    CALL LocalButton.Select 0
    CALL RemoteButton.Select 1
    CALL RemoteButton.Focus
    CALL SetupButton.Enable
  END
ELSE
  DO
    CALL SetupButton.Disable
    RemoteFlag = 0
  END
CommandSocket = -1
ServerPort = INIget(OurINI,"iedr","Port")
IF ServerPort = "" THEN ServerPort = 3560
ServerAddress = INIget(OurINI,"iedr","Host")
IF ServerAddress = "" THEN ServerAddress = '127.0.0.1'
Password = INIget(OurINI,"iedr","Password")
IF Password = "" THEN Password = ""
RB = ""
��Click3CALL INIput OurINI,"iedr","Remote",RemoteFlag
EXIT��ClickeCALL Status.Text ""
CALL ModalFor 'SetupDialogue'
CALL SetupDialogue.Close
CALL MainDialogue.Focus��Click�IF RemoteFlag THEN rc = ConnectToServer()
ELSE rc = 1
IF rc THEN
  DO
    CALL Status.Text "Editing"
    PUSH RemoteFlag
    CALL ModalFor 'EditINIFile'
    CALL EditINIFile.Close
    IF RemoteFlag THEN CALL ExecCmd "Q"
    CALL Status.Text ""
  END��Click'RemoteFlag = 1
CALL SetupButton.EnableInitCALL Select RemoteFlag��ClickmRemoteFlag = RemoteButton.Select()
IF RemoteFlag THEN CALL SetupButton.Enable
ELSE CALL SetupButton.Disable�� �� 0l  l  �  ��    	      :  �K� ?� � ��K         O � U � E f P��         i �� U � E g j��        �� � 6  e ���        � �� � $  � ���         � �  8> h ���        �� K $ 
 � ���        �  9 i ��         8
    W 6O � 9��         R
     7H � S��Editing INI File 3             9.WarpSans             9.WarpSans   Application          9.WarpSans   Key          9.WarpSans    .      &   10.System Monospaced                  Value          9.WarpSans   Message          9.WarpSans             9.WarpSans             9.WarpSans   � �� 0    �      ~File &   �      ~Open ...     ~Exit     ~Rename (   �      ~Application    	 ~Key    
 ~Edit *   �      ~ASCII     ~Hexadecimal     ~Add (   �      ~Application     ~Key     ~Delete (   �      ~Application     ~Key ���� 0    �IF RemoteFlag THEN
  DO
    newname = ModalFor('OpenDialogue')
    CALL OpenDialogue.Close
  END
ELSE newname = FilePrompt('*.?NI')
IF newname \= '' THEN INIFile = newname
CALL EditINIFile.Text INIFile
CALL LoadApps
  /CALL EditINIFile.Close
CALL MainDialogue.Focus  �oldapp = AppList.Item(AppNumber)
PUSH oldapp
PUSH 'New application name'
newapp = ModalFor('EditOneString')
CALL EditOneString.Close
IF (newapp \= '') & (newapp \= oldapp) THEN
DO
  CALL INIGetKeys oldapp, 'K.'
  DO j=1 TO K.0
    CALL INISetValue newapp, K.j, INIGetValue(oldapp,K.j)
  END
  CALL INIDeleteApp oldapp
  CALL LoadApps
  j = 1
  DO WHILE AppList.Item(j) \= newapp
    j = j+1
  END
  CALL AppList.Select(j)
END	  �app = AppList.Item(AppNumber)
oldkey = KeyList.Item(KeyNumber)
PUSH oldkey
PUSH 'New key name'
newkey = ModalFor('EditOneString')
CALL EditOneString.Close
IF (newkey \= '') & (newkey \= oldkey) THEN
DO
  CALL INISetValue app, newkey, INIGetValue(app,oldkey)
  CALL INIDeleteKey app, oldkey
  CALL LoadKeys
  j = 1
  DO WHILE KeyList.Item(j) \= newkey
    j = j+1
  END
  CALL KeyList.Select(j)
END  �PUSH 'A'
PUSH AppList.Item(AppNumber)
PUSH KeyList.Item(KeyNumber)
ans = ModalFor('EditDialogue')
CALL EditDialogue.Close
CALL LoadValue  �PUSH 'H'
PUSH AppList.Item(AppNumber)
PUSH KeyList.Item(KeyNumber)
ans = ModalFor('EditDialogue')
CALL EditDialogue.Close
CALL LoadValue  �PUSH ''
PUSH 'New application'
Newapp = ModalFor('EditOneString')
CALL INISetValue Newapp, '?', ''
CALL EditOneString.Close
CALL LoadApps
j = 1
DO WHILE AppList.Item(j) \= Newapp
  j = j+1
END
CALL AppList.Select(j)  �PUSH ''
PUSH 'New key'
Newkey = ModalFor('EditOneString')
CALL INISetValue AppList.Item(AppNumber), Newkey, ''
CALL EditOneString.Close
CALL LoadKeys
j = 1
DO WHILE KeyList.Item(j) \= Newkey
  j = j+1
END
CALL KeyList.Select(j)  8CALL INIDeleteApp AppList.Item(AppNumber)
CALL LoadApps  QCALL INIDeleteKey AppList.Item(AppNumber), KeyList.Item(KeyNumber)
CALL LoadKeys���� 0�  �� InitLINIFile = 'No file selected'
HILITE = "#0 0 255"
NOHILITE = "#150 150 150"Open$PULL RemoteFlag
CALL Text INIFile
Exit	RETURN OK�h 	LoseFocusCALL Color 'H-', NOHILITEGetFocusCALL Color 'H-', HILITE�g 	LoseFocusCALL Color 'H-', NOHILITEGetFocusCALL Color 'H-', HILITESelect$KeyNumber = Select()
CALL LoadValue�f 	LoseFocusCALL Color 'H-', NOHILITEGetFocusCALL Color 'H-', HILITESelect1AppNumber = Select()
CALL LoadKeys
CALL Focus
�� �,0�  �  �  ��           �   �@� � k ,���         � ^ 1 
 -��         ' �9 ^ h 
 .(��        @ � T 1 
 0D��         \ �9 T h 
 /]��      
   u �  � ; 1v��        �  �$  ( 
 2���        �  �a  ( 
 3���    Application          9.WarpSans            9.WarpSans  Key          9.WarpSans            9.WarpSans            9.WarpSans  OK          9.WarpSans  Cancel          9.WarpSans  ���,0  �,Open�PARSE PULL key
PARSE PULL app
PARSE PULL AsciiFlag
val = INIGetValue(app, key)
CALL AppBox.Text app
CALL KeyBox.Text key
IF AsciiFlag='A' THEN
  DO
    CALL Text 'Editing value (ASCII)'
  END
ELSE
  DO
    CALL Text 'Editing value (Hexadecimal)'
    val = C2XS(val)
  END
CALL ValBox.Text val�3Click	RETURN ''�2Click�val = ValBox.Text()
IF AsciiFlag = 'H' THEN
  DO
    val = TRANSLATE(val,'  ','0A0D'X)
    val = X2C(SPACE(val,0))
  END
CALL INISetValue app, key,val
RETURN 'OK'�� ��0�   �   �  ��           h   �k � �  ���i          m  �  �  �n �          �   a  ( 
 �� ��              9.WarpSans                 9.WarpSans ����0u   ��InitLPARSE PULL Label
CALL Text Label
PARSE PULL value
CALL DataBox.Text value��ClickRETURN DataBox.Text()�� ��0    �  ��          �   �� � k ����          �  �  � Z �� ��        �   �  ( 
 �� ��        �   �h  ( 
 �� ��Open Remote File ...     !                  9.WarpSans   Open !                  9.WarpSans   Cancel !                  9.WarpSans   ����0�  ��OpenFilePath = ''
CALL FillList��Click	RETURN ''��Click�j = FileList.Select()
IF j=0 THEN RETURN ''
name = FileList.Item(j)
IF name = '' THEN RETURN ''
IF ExecCmd("C"||name) THEN CALL FillList
ELSE IF ExecCmd("F"||name) THEN RETURN FilePath||name
ELSE RETURN ''��Enter�name = Item(Select())
IF name = '' THEN RETURN ''
IF ExecCmd("C"||name) THEN CALL FillList
ELSE IF ExecCmd("F"||name) THEN RETURN FilePath||name
ELSE RETURN ''�� �X0�  �  �  ��          � �  �� � � & X��        �  3 
 Y!��         9 �7  f  Z:��        R �  3 
 \W��         o �7  f  [p��        �  `  ( 
 a���        � �  3 
 `���         � �7  f  _���Remote server details #   Hostname          9.WarpSans            9.WarpSans  Port          9.WarpSans            9.WarpSans  Push          9.WarpSans  Password          9.WarpSans            9.WarpSans  ���X0  �XExit�CALL INIput OurINI,"iedr","Host",ServerAddress
CALL INIput OurINI,"iedr","Port",ServerPort
CALL INIput OurINI,"iedr","Password",Password
CALL MainDialogue.Focus�_ChangedPassword = Text()InitCALL Text Password�aClick�CALL INIput OurINI,"iedr","Host",ServerAddress
CALL INIput OurINI,"iedr","Port",ServerPort
CALL INIput OurINI,"iedr","Password",Password
RETURN 'OK'�[ChangedServerPort = Text()

InitCALL Text ServerPort�ZChangedServerAddress = Text()InitCALL Text ServerAddress�