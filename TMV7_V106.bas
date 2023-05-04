'#############################################################################################################
'
' TMV7_LCD.BAS
'
'-------------------------------------------------------------------------------------------------------------
'
' Version 1.06 "Bug-Free" - All remaining bugs are property of Kenwood :-)
'
' LCD-Interface to connect a Hitachi 44780 compatible
' display to a Kenwood TM-V7 Transceiver via the data port.
' My display isn't 100% true HD44780, so I had to use
' Config Lcd = 20 * 4 , Chipset = Ks077
' Omit Chipset = ... for true 44780s
'
' Ing. Mario Kienspergher, OE9MKV
' Kinzi Design - Copyright (c) 2005-2009.
' http://www.kinzi.net/
' http://www.oe9mkv.net/
'
' Supported commands:
'
'     123456789.123456789.123456789.123456789.123456789.
' BUF 0,00145650000,3,3,0,0,0,0,09,000,09,006000000
'  VMC 0,2
'   MC 0,011
'   PC 0,2
'   PG 0,1
'   BC 0,0
'   AI 1
'   ID TM-V7
'   SM 0,07
'   BY 0,1
'
'-------------------------------------------------------------------------------------------------------------
'
' TM-V7 connections (TTL levels):
'
' 2 - GND
' 3 - Receive Data (TM-V7 input)
' 6 - Transmit Data (TM-V7 output)
'
' Connect pins 4 and 5 at TM-V7 to enable CAT-interface.
'
'-------------------------------------------------------------------------------------------------------------
'
' Controller pinout:
'
' Portc.3...0 = DB7...DB4
' Portc.4     = E
' Portc.5     = R/S
'
' Portd.1     = TXD RS232
' Portd.0     = RXD RS232
'
'-------------------------------------------------------------------------------------------------------------
'
' Using a 4 x 20 character display
'
'  12345678901234567890
' +--------------------+
' ![V] ######## RDCT BP!
' !H  145.650.00 -0.600!
' !001 ###FFF.F RDCT BP!
' !H  438.875.00 =7.600!
' +--------------------+
'
'  H ... Power-Level (H/M/L)
'  T ... CTCSS-Tone transmit active (inverse T)
'  C ... CTCSS-Tone receive active (inverse T)
'  D ... DTSS system active (inverse D)
'  R ... Reverse shift mode marker (inverse R)
'  B ... Control Band Flag (inverse C)
'  P ... Transmit Band Flag (inverse P)
'  # ... Meter level indicator, or alternatively
'  F ... CTCSS-frequency (when activated and no signal meter)
'
'-------------------------------------------------------------------------------------------------------------
' Compiler directives
'-------------------------------------------------------------------------------------------------------------

$baud = 9600                                                                                                  ' 9600 baud serial line
$crystal = 8000000                                                                                            ' internal clock runs at 8.000000 MHz
$regfile = "m8def.dat"

'-------------------------------------------------------------------------------------------------------------
' Controller configuration
'-------------------------------------------------------------------------------------------------------------

Config Lcd = 20 * 4 , Chipset = Ks077                                                                         ' Omit "Chipset = Ks077" for true HD44780 displays
Config Lcdpin = Pin , Db4 = Portc.0 , Db5 = Portc.1 , Db6 = Portc.2 , Db7 = Portc.3 , E = Portc.5 , Rs = Portc.4
Config Com1 = Dummy , Synchrone = 0 , Parity = None , Stopbits = 1 , Databits = 8 , Clockpol = 0

'-------------------------------------------------------------------------------------------------------------
' Interrupt configuration
'-------------------------------------------------------------------------------------------------------------

Disable Interrupts
Disable Urxc
On Urxc Isr_char_received

'-------------------------------------------------------------------------------------------------------------
' Constants
'-------------------------------------------------------------------------------------------------------------

Const Con_max_fifo_depth = 9
Const Con_max_fifo_pointer = 10

'-------------------------------------------------------------------------------------------------------------
' Variables
'-------------------------------------------------------------------------------------------------------------

Dim Str_tmv7_cmd_fifo(10) As String * 5
Dim Str_tmv7_par_fifo(10) As String * 50
Dim Byt_tmv7_fifo_input_pointer As Byte
Dim Byt_tmv7_fifo_parse_pointer As Byte
Dim Byt_tmv7_fifo_depth As Byte
Dim Byt_tmv7_cmd_par_mode As Byte

Dim Byt_tmv7_received_char As Byte
Dim Str_dummy As String * 20                                                                                  ' Input buffer for TM-V7 messages
Dim Byt_dummy As Byte

Dim Str_tmv7_freq(2) As String * 15
Dim Str_tmv7_shift(2) As String * 12
Dim Str_tmv7_vmc_mode(2) As String * 4
Dim Str_tmv7_power_control(2) As String * 3
Dim Str_tmv7_paging_control(2) As String * 1
Dim Str_tmv7_signal_level(2) As String * 9
Dim Str_tmv7_busy_status(2) As String * 1
Dim Str_tmv7_tone_mode(2) As String * 2
Dim Str_tmv7_reverse_mode(2) As String * 1
Dim Byt_tmv7_tone_value(2) As Byte

Dim Str_tmv7_ai_str As String * 1
Dim Str_tmv7_id_str As String * 5
Dim Str_tmv7_par_str As String * 50

Dim Str_tmv7_ptt_status As String * 1                                                                         ' "?" / "R" / "T" / "!"
Dim Byt_tmv7_transmit_band As Byte                                                                            ' 0 = Band "0" , 1 = Band "1"
Dim Byt_tmv7_control_band As Byte                                                                             ' 0 = Band "0" , 1 = Band "1"
Dim Byt_tmv7_message_band As Byte                                                                             ' 0 = Band "0" , 1 = Band "1"

'#############################################################################################################
' Main program
'#############################################################################################################

Main:

Ddrc = &B11111111                                                                                             ' All Port.b pins are outputs
Portc = &B11111111                                                                                            ' Enables pull-ups on PORTB when PORTB lines are inputs

Ddrd = &B00000010                                                                                             ' All Port.d pins are inputs except TXD (Portd.1)
Portd = &B11111111                                                                                            ' Enables pull-ups on PORTD when PORTD lines are inputs

'-------------------------------------------------------------------------------------------------------------
' Initialize TM-V7 status and other variables
'-------------------------------------------------------------------------------------------------------------

Byt_tmv7_received_char = 0

Str_dummy = ""
Byt_dummy = 0

Str_tmv7_freq(1) = ""
Str_tmv7_shift(1) = ""
Str_tmv7_vmc_mode(1) = "0"
Str_tmv7_power_control(1) = " "
Str_tmv7_paging_control(1) = " "
Str_tmv7_signal_level(1) = ""
Str_tmv7_busy_status(1) = ""
Str_tmv7_tone_mode(1) = "  "
Str_tmv7_reverse_mode(1) = ""
Byt_tmv7_tone_value(1) = 0

Str_tmv7_freq(2) = ""
Str_tmv7_shift(2) = ""
Str_tmv7_vmc_mode(2) = "0"
Str_tmv7_power_control(2) = " "
Str_tmv7_paging_control(2) = " "
Str_tmv7_signal_level(2) = ""
Str_tmv7_busy_status(2) = ""
Str_tmv7_tone_mode(2) = "  "
Str_tmv7_reverse_mode(2) = ""
Byt_tmv7_tone_value(2) = 0

Str_tmv7_ai_str = ""
Str_tmv7_id_str = "unkwn"
Str_tmv7_par_str = ""

Str_tmv7_ptt_status = "?"
Byt_tmv7_transmit_band = 0
Byt_tmv7_control_band = 0
Byt_tmv7_message_band = 0

For Byt_tmv7_fifo_input_pointer = 1 To 10
   Str_tmv7_cmd_fifo(byt_tmv7_fifo_input_pointer) = ""
   Str_tmv7_par_fifo(byt_tmv7_fifo_input_pointer) = ""
Next Byt_tmv7_fifo_input_pointer

Byt_tmv7_fifo_input_pointer = 1
Byt_tmv7_fifo_parse_pointer = 1
Byt_tmv7_cmd_par_mode = 0
Byt_tmv7_fifo_depth = 0

'-------------------------------------------------------------------------------------------------------------
' Initialize LCD display and display copyright
'-------------------------------------------------------------------------------------------------------------

Waitms 100                                                                                                    ' Let voltages settle on LCD

Deflcdchar 0 , 31 , 17 , 21 , 17 , 23 , 23 , 31 , 32                                                          ' Inverse "P" - PTT band marker
Deflcdchar 1 , 31 , 17 , 23 , 23 , 23 , 17 , 31 , 32                                                          ' Inverse "C" - CTRL band marker
Deflcdchar 2 , 31 , 19 , 21 , 21 , 21 , 19 , 31 , 32                                                          ' Inverse "D" - DTSS indicator
Deflcdchar 3 , 31 , 17 , 21 , 17 , 19 , 21 , 31 , 32                                                          ' Inverse "R" - Reverse shift marker
Deflcdchar 4 , 31 , 17 , 27 , 27 , 27 , 27 , 31 , 32                                                          ' Inverse "T" - CTCSS marker

Deflcdchar 5 , 32 , 32 , 32 , 32 , 32 , 31 , 31 , 32                                                          ' Bargraph 1
Deflcdchar 6 , 32 , 32 , 32 , 32 , 31 , 31 , 31 , 32                                                          ' Bargraph 2
Deflcdchar 7 , 32 , 32 , 32 , 31 , 31 , 31 , 31 , 32                                                          ' Bargraph 3

' It is important that a CLS is following the "Deflcdchar" statements because
' it will set the controller back to datamode

Cls                                                                                                           ' select data RAM
Cursor Off Noblink                                                                                            ' hide cursor

Lcd "TM-V7 LCD Vers. 1.06"                                                                                    ' tell the user who we are :-)
Lowerline
Lcd "ATmega8, 9k6, Int.RC"
Thirdline
Lcd " (c) 04/2009 OE9MKV "
Fourthline
Lcd " Transceiver:       "
Locate 4 , 15

'-------------------------------------------------------------------------------------------------------------
' Initialize communication with TM-V7
'-------------------------------------------------------------------------------------------------------------


Print "AI 0" ; Chr(13) ;                                                                                      ' tell the transceiver to be quiet
Waitms 50
Print "AI 0" ; Chr(13) ;                                                                                      ' twice to be sure it understands
Waitms 250

Enable Interrupts
Enable Urxc

Print "ID" ; Chr(13) ;                                                                                        ' identify the transceiver model
Waitms 250
Print "ID" ; Chr(13) ;                                                                                        ' twice to be sure it understands
Waitms 250
Gosub Sub_parse_messages                                                                                      ' analyze the tranceiver's answers
Lcd Str_tmv7_id_str
Waitms 2000

Locate 4 , 1
Lcd "Init:               "
Locate 4 , 7

Restore Lbl_tmv7_init_sequence
Read Str_dummy

While Str_dummy <> "THE_END"                                                                                  ' start transceiver initialization sequence
   Print Str_dummy ; Chr(13) ;
   Lcd Chr(255)
   Waitms 100
   Gosub Sub_parse_messages
   Read Str_dummy
Wend

Cls
                                                                                                    ' Main program loop following
Do
   Gosub Sub_parse_messages

   Locate 1 , 1                                                                                               ' Now display all parameters for band 0
   Lcd Left(str_tmv7_vmc_mode(1) , 3) ; " "

   Locate 1 , 4
   Lcd " "

   If Str_tmv7_busy_status(1) = "1" Then
         Lcd Left(str_tmv7_signal_level(1) , 8)
      Elseif Str_tmv7_ptt_status = "T" And Byt_tmv7_transmit_band = 0 Then
            Lcd Left(str_tmv7_signal_level(1) , 8)
         Elseif Str_tmv7_tone_mode(1) = "  " Then
                     Lcd "        "
                  Else
                     Lcd "   "
                     Str_dummy = Lookupstr(byt_tmv7_tone_value(1) , Lbl_ctcss_values)
                     Lcd Left(str_dummy , 5) ; "  "
   End If

   Locate 1 , 13
   Lcd " "
   Lcd Left(str_tmv7_reverse_mode(1) , 1)
   Lcd Left(str_tmv7_paging_control(1) , 1)
   Lcd Left(str_tmv7_tone_mode(1) , 2)
   Lcd " "

   Locate 1 , 18
   If Byt_tmv7_control_band = 0 Then
         Lcd " " ; Chr(1)
      Else
         Lcd "  "
   End If

   Locate 1 , 20
   If Byt_tmv7_transmit_band = 0 Then
         Lcd Chr(0)
      Else
         Lcd " "
   End If

   Locate 2 , 1
   Lcd Left(str_tmv7_power_control(1) , 1) ; " "

   Locate 2 , 4
   Lcd Left(str_tmv7_freq(1) , 10) ; " "

   Locate 2 , 14
   Lcd " " ; Left(str_tmv7_shift(1) , 6)

   Gosub Sub_parse_messages

   Locate 3 , 1                                                                                               ' Now display all parameters for band 1
   Lcd Left(str_tmv7_vmc_mode(2) , 3) ; " "

   Locate 3 , 4
   Lcd " "

   If Str_tmv7_busy_status(2) = "1" Then
         Lcd Left(str_tmv7_signal_level(2) , 8)
      Elseif Str_tmv7_ptt_status = "T" And Byt_tmv7_transmit_band = 1 Then
            Lcd Left(str_tmv7_signal_level(2) , 8)
         Elseif Str_tmv7_tone_mode(2) = "  " Then
                     Lcd "        "
                  Else
                     Lcd "   "
                     Str_dummy = Lookupstr(byt_tmv7_tone_value(2) , Lbl_ctcss_values)
                     Lcd Left(str_dummy , 5) ; "  "
   End If

   Locate 3 , 13
   Lcd " "
   Lcd Left(str_tmv7_reverse_mode(2) , 1)
   Lcd Left(str_tmv7_paging_control(2) , 1)
   Lcd Left(str_tmv7_tone_mode(2) , 2)
   Lcd " "

   Locate 3 , 18
   If Byt_tmv7_control_band = 1 Then
         Lcd " " ; Chr(1)
      Else
         Lcd "  "
   End If
   Locate 3 , 20
   If Byt_tmv7_transmit_band = 1 Then
         Lcd Chr(0)
      Else
         Lcd " "
   End If

   Locate 4 , 1
   Lcd Left(str_tmv7_power_control(2) , 1) ; " "

   Locate 4 , 4
   Lcd Left(str_tmv7_freq(2) , 10) ; " "

   Locate 4 , 14
   Lcd " " ; Left(str_tmv7_shift(2) , 6)

Loop

'#############################################################################################################
' Subroutines and functions
'#############################################################################################################

'-------------------------------------------------------------------------------------------------------------
' "Sub_parse_messages" - parse saved strings
'-------------------------------------------------------------------------------------------------------------

Sub_parse_messages:

While Byt_tmv7_fifo_depth > 0

   Select Case Str_tmv7_cmd_fifo(byt_tmv7_fifo_parse_pointer)

      Case "?" :                                                                                              ' error, do nothing
      Case "N" :                                                                                              ' error, do nothing
      Case "E" :                                                                                              ' error, do nothing
      Case "RX" : Str_tmv7_ptt_status = "R"                                                                   ' receiving
      Case "TX" : Str_tmv7_ptt_status = "T"                                                                   ' transceiver is transmitting
      Case "TT" : Str_tmv7_ptt_status = "!"                                                                   ' transmitting is transmitting 1750 Hz tone
      Case "ID" : Str_tmv7_id_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                            ' transceiver identification string
      Case "AI" : Str_tmv7_ai_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                            ' auto information update function

      Case "VMC" : Str_tmv7_par_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                          ' VMC b,m = VFO (m=0), call (m=3) or memory (m=2) mode on band "b" active
                     If Len(str_tmv7_par_str) = 3 Then
                        Str_dummy = Left(str_tmv7_par_str , 1)
                        Byt_tmv7_message_band = Val(str_dummy)
                        Str_dummy = Right(str_tmv7_par_str , 1)
                        Byt_dummy = Val(str_dummy)
                        Select Case Byt_dummy
                           Case 0 : Str_dummy = "[V]"
                           Case 3 : Str_dummy = "[C]"
                        End Select
                        Str_tmv7_vmc_mode(byt_tmv7_message_band + 1) = Str_dummy
                     End If

      Case "MC" : Str_tmv7_par_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                           ' MC b,ccc = actual memory channel number "ccc" for band "b"
                  If Len(str_tmv7_par_str) = 4 Then Str_tmv7_par_str = Str_tmv7_par_str + " "
                  If Len(str_tmv7_par_str) = 5 Then
                     Str_dummy = Left(str_tmv7_par_str , 1)
                     Byt_tmv7_message_band = Val(str_dummy)
                     Str_tmv7_vmc_mode(byt_tmv7_message_band + 1) = Right(str_tmv7_par_str , 3)
                  End If

      Case "BC" : Str_tmv7_par_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                           ' BC c,t = c=control band (0/1), t=transmit band (0/1)
                  If Len(str_tmv7_par_str) = 3 Then
                     Str_dummy = Left(str_tmv7_par_str , 1)
                     Byt_tmv7_control_band = Val(str_dummy)
                     Str_dummy = Right(str_tmv7_par_str , 1)
                     Byt_tmv7_transmit_band = Val(str_dummy)
                  End If

      Case "PC" : Str_tmv7_par_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                           ' PC b,l =  Power level high (0), medium (1) or low (2) on band "b" selected
                  If Len(str_tmv7_par_str) = 3 Then
                     Str_dummy = Left(str_tmv7_par_str , 1)
                     Byt_tmv7_message_band = Val(str_dummy)
                     Str_dummy = Right(str_tmv7_par_str , 1)
                     Byt_dummy = Val(str_dummy)
                     Select Case Byt_dummy
                        Case 0 : Str_dummy = "H"
                        Case 1 : Str_dummy = "M"
                        Case 2 : Str_dummy = "L"
                     End Select
                     Str_tmv7_power_control(byt_tmv7_message_band + 1) = Str_dummy
                  End If

      Case "PG" : Str_tmv7_par_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                           ' PG b,p = Paging mode on (1) or off (0) on band "b"
                  If Len(str_tmv7_par_str) = 3 Then
                     Str_dummy = Left(str_tmv7_par_str , 1)
                     Byt_tmv7_message_band = Val(str_dummy)
                     Str_dummy = Right(str_tmv7_par_str , 1)
                     Byt_dummy = Val(str_dummy)
                     If Byt_dummy = 1 Then
                           Str_dummy = Chr(2)                                                                 ' "inverse D"
                        Else
                           Str_dummy = " "
                     End If
                     Str_tmv7_paging_control(byt_tmv7_message_band + 1) = Str_dummy
                  End If

      Case "SM" : Str_tmv7_par_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                           ' SM b,l = Signal meter level (l=0..7) on band "b"
                  If Len(str_tmv7_par_str) = 4 Then
                     Str_dummy = Left(str_tmv7_par_str , 1)
                     Byt_tmv7_message_band = Val(str_dummy)

                     Str_dummy = Right(str_tmv7_par_str , 2)
                     Byt_dummy = Val(str_dummy) + 1

                     Str_dummy = "__" + Chr(5) + Chr(5) + Chr(6) + Chr(6) + Chr(7) + Chr(7)
                     Str_dummy = Left(str_dummy , Byt_dummy)
                     Byt_dummy = 8 - Byt_dummy
                     If Byt_dummy > 0 Then Str_dummy = Str_dummy + Space(byt_dummy)
                     Str_tmv7_signal_level(byt_tmv7_message_band + 1) = Str_dummy
                  End If

      Case "BY" : Str_tmv7_par_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                           ' BY b,s = Busy status change to free (0) or busy (1) on band "b"
                  If Len(str_tmv7_par_str) = 3 Then
                     Str_dummy = Left(str_tmv7_par_str , 1)
                     Byt_tmv7_message_band = Val(str_dummy)
                     Str_dummy = Right(str_tmv7_par_str , 1)
                     Str_tmv7_busy_status(byt_tmv7_message_band + 1) = Str_dummy
                  End If

      Case "BUF" : Str_tmv7_par_str = Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer)                          ' BUF b,... = contents of buffer on band "b"
                     If Len(str_tmv7_par_str) = 45 Then
                        Str_dummy = Left(str_tmv7_par_str , 1)
                        Byt_tmv7_message_band = Val(str_dummy)
                        Str_tmv7_freq(byt_tmv7_message_band + 1) = Mid(str_tmv7_par_str , 5 , 3) + "." + _
                                                           Mid(str_tmv7_par_str , 8 , 3) + "." + _
                                                           Mid(str_tmv7_par_str , 11 , 2)
                        Str_dummy = Mid(str_tmv7_par_str , 17 , 1)                                            ' Read shift mode
                        Byt_dummy = Val(str_dummy)
                        Str_dummy = Mid(str_tmv7_par_str , 19 , 1)                                            ' Read reverse mode
                        If Str_dummy = "1" Then
                              Byt_dummy = Byt_dummy + 10                                                      ' Mark reverse mode
                              Str_tmv7_reverse_mode(byt_tmv7_message_band + 1) = Chr(3)
                           Else
                              Str_tmv7_reverse_mode(byt_tmv7_message_band + 1) = Chr(32)
                        End If
                        Str_dummy = " 0.000"
                        Select Case Byt_dummy
                           Case 1 : Str_dummy = "+" + Mid(str_tmv7_par_str , 39 , 1) + "." + Mid(str_tmv7_par_str , 40 , 3)
                           Case 2 : Str_dummy = "-" + Mid(str_tmv7_par_str , 39 , 1) + "." + Mid(str_tmv7_par_str , 40 , 3)
                           Case 3 : Str_dummy = "=7.600"                                                      ' Special UHF-shift (fix -7.6MHz)
                           ' Reverse modes following
                           Case 11 : Str_dummy = "-" + Mid(str_tmv7_par_str , 39 , 1) + "." + Mid(str_tmv7_par_str , 40 , 3)
                           Case 12 : Str_dummy = "+" + Mid(str_tmv7_par_str , 39 , 1) + "." + Mid(str_tmv7_par_str , 40 , 3)
                           Case 13 : Str_dummy = "#7.600"                                                     ' Special UHF-shift (fix +7.6MHz)
                        End Select
                        Str_tmv7_shift(byt_tmv7_message_band + 1) = Str_dummy

                        Str_tmv7_tone_mode(byt_tmv7_message_band + 1) = "  "

                        Str_dummy = Mid(str_tmv7_par_str , 21 , 1)                                            ' Pos 21 = "T" mode
                        If Str_dummy = "1" Then
                           Str_tmv7_tone_mode(byt_tmv7_message_band + 1) = " " + Chr(4)                       ' " T"
                           Str_dummy = Mid(str_tmv7_par_str , 27 , 2)                                         ' CTCSS tone
                           Byt_tmv7_tone_value(byt_tmv7_message_band + 1 ) = Val(str_dummy)
                        End If

                        Str_dummy = Mid(str_tmv7_par_str , 23 , 1)                                            ' Pos 23 = "CT" mode
                        If Str_dummy = "1" Then
                           Str_tmv7_tone_mode(byt_tmv7_message_band + 1) = Chr(1) + Chr(4)                    ' "CT"
                           Str_dummy = Mid(str_tmv7_par_str , 34 , 2)                                         ' CTCSS tone
                           Byt_tmv7_tone_value(byt_tmv7_message_band + 1 ) = Val(str_dummy)
                        End If

                        Str_dummy = Mid(str_tmv7_par_str , 25 , 1)                                            ' Pos 21 = "T", Pos 23 = "CT", Pos 25 = "DT"
                        If Str_dummy = "1" Then Str_tmv7_paging_control(byt_tmv7_message_band + 1) = Chr(2)

                        Str_tmv7_busy_status(byt_tmv7_message_band + 1) = "0"                                 ' Bugfix: TM-V7 doesn't send BY x,0 when changing buffer ... very odd!

                     End If

   End Select

   Str_tmv7_cmd_fifo(byt_tmv7_fifo_parse_pointer) = ""
   Str_tmv7_par_fifo(byt_tmv7_fifo_parse_pointer) = ""
   Incr Byt_tmv7_fifo_parse_pointer
   If Byt_tmv7_fifo_parse_pointer > Con_max_fifo_pointer Then Byt_tmv7_fifo_parse_pointer = 1
   Decr Byt_tmv7_fifo_depth

Wend

Return

'-------------------------------------------------------------------------------------------------------------
' ISR
' Runs on serial interrupt (receive char)
'-------------------------------------------------------------------------------------------------------------

Isr_char_received:

Byt_tmv7_received_char = Inkey()                                                                              ' Get char from USART-FIFO

Select Case Byt_tmv7_received_char

   Case 32 : Byt_tmv7_cmd_par_mode = 1                                                                        ' 32 = blank -> command received, parameters following

   Case 13 : Incr Byt_tmv7_fifo_input_pointer                                                                 ' 13 = end of line -> now store received command resp. parameters
             If Byt_tmv7_fifo_input_pointer > Con_max_fifo_pointer Then Byt_tmv7_fifo_input_pointer = 1
             Incr Byt_tmv7_fifo_depth
             If Byt_tmv7_fifo_depth > Con_max_fifo_depth Then Byt_tmv7_fifo_depth = Con_max_fifo_depth        ' oldest message will be discarded if buffers overflows
             Byt_tmv7_cmd_par_mode = 0

   Case Else : If Byt_tmv7_cmd_par_mode = 0 Then                                                              ' store received characters in FIFO
                     Str_tmv7_cmd_fifo(byt_tmv7_fifo_input_pointer) = Str_tmv7_cmd_fifo(byt_tmv7_fifo_input_pointer) + Chr(byt_tmv7_received_char)
                  Else
                     Str_tmv7_par_fifo(byt_tmv7_fifo_input_pointer) = Str_tmv7_par_fifo(byt_tmv7_fifo_input_pointer) + Chr(byt_tmv7_received_char)
               End If
End Select

Return                                                                                                        ' RETI - Return from interrupt

'-------------------------------------------------------------------------------------------------------------
' End Of Program
'-------------------------------------------------------------------------------------------------------------

End

'#############################################################################################################
' Data storage
'#############################################################################################################

Lbl_tmv7_init_sequence:
Data "RX"                                                                                                     ' for safety reasons tell the transceiver to stop transmitting
Data "SC 0,0" , "SC 1,0"                                                                                      ' stop scanning on both bands to minimize serial traffic
Data "SM 0" , "PC 0" , "VMC 0" , "MC 0" , "BUF 0"                                                             ' check status of band 0
Data "SM 1" , "PC 1" , "VMC 1" , "MC 1" , "BUF 1"                                                             ' check status of band 1
Data "BC"                                                                                                     ' check which band is selected for control and transmitting
Data "AI 1"                                                                                                   ' tell the transceiver to be verbose about its activities
Data "THE_END"                                                                                                ' End of initialization sequence

Lbl_ctcss_values:
Data "  0.0" , "  0.0"                                                                                        ' Offsets for TM-V7 compatible counting - never used
Data " 67.0" , " 71.9" , " 74.4" , " 77.0" , " 79.7" , " 82.5" , " 85.4"
Data " 88.5" , " 91.5" , " 94.8" , " 97.4" , "100.0" , "103.5" , "107.2"
Data "110.9" , "114.8" , "118.8" , "123.0" , "127.3" , "131.8" , "136.5"
Data "141.3" , "146.2" , "151.4" , "156.7" , "162.2" , "167.9" , "173.8"
Data "179.9" , "186.2" , "192.8" , "203.5" , "210.7" , "218.1" , "225.7"
Data "233.6" , "241.8" , "250.3" , " 1750"