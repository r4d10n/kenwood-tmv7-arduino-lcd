//#############################################################################################################
//
// TMV7 LCD control using Arduino - Ported from Bascom implementation by Kinzi/OE9MKV using Sage LLM :)
// WIP: Basic structure ported. 
//
//-------------------------------------------------------------------------------------------------------------
// Original Header:
//
// Version 1.06 "Bug-Free" - All remaining bugs are property of Kenwood :-)
//
// LCD-Interface to connect a Hitachi 44780 compatible
// display to a Kenwood TM-V7 Transceiver via the data port.
// My display isn//t 100% true HD44780, so I had to use
// Config Lcd = 20 * 4 , Chipset = Ks077
// Omit Chipset = ... for true 44780s
//
// Ing. Mario Kienspergher, OE9MKV
// Kinzi Design - Copyright (c) 2005-2009.
// http://www.kinzi.net/
// http://www.oe9mkv.net/
//
// Supported commands:
//
//     123456789.123456789.123456789.123456789.123456789.
// BUF 0,00145650000,3,3,0,0,0,0,09,000,09,006000000
//  VMC 0,2
//   MC 0,011
//   PC 0,2
//   PG 0,1
//   BC 0,0
//   AI 1
//   ID TM-V7
//   SM 0,07
//   BY 0,1
//
//-------------------------------------------------------------------------------------------------------------
//
// TM-V7 connections (TTL levels):
//
// 2 - GND
// 3 - Receive Data (TM-V7 input)
// 6 - Transmit Data (TM-V7 output)
//
// Connect pins 4 and 5 at TM-V7 to enable CAT-interface.
//
//-------------------------------------------------------------------------------------------------------------
//
// Controller pinout:
//
// Portc.3...0 = DB7...DB4
// Portc.4     = E
// Portc.5     = R/S
//
// Portd.1     = TXD RS232
// Portd.0     = RXD RS232
//
//-------------------------------------------------------------------------------------------------------------
//
// Using a 4 x 20 character display
//
//  12345678901234567890
// +--------------------+
// ![V] ######## RDCT BP!
// !H  145.650.00 -0.600!
// !001 ###FFF.F RDCT BP!
// !H  438.875.00 =7.600!
// +--------------------+
//
//  H ... Power-Level (H/M/L)
//  T ... CTCSS-Tone transmit active (inverse T)
//  C ... CTCSS-Tone receive active (inverse T)
//  D ... DTSS system active (inverse D)
//  R ... Reverse shift mode marker (inverse R)
//  B ... Control Band Flag (inverse C)
//  P ... Transmit Band Flag (inverse P)
//  # ... Meter level indicator, or alternatively
//  F ... CTCSS-frequency (when activated and no signal meter)
//


#include <stdio.h>
#include <string.h>

#define STR_SIZE 6
#define CMD_FIFO_SIZE 11
#define PAR_FIFO_SIZE 11

const float ctcss_values[] = {
  0.0, 0.0, 67.0, 71.9, 74.4, 77.0, 79.7, 82.5, 85.4, 88.5, 91.5, 94.8, 97.4, 100.0,
  103.5, 107.2, 110.9, 114.8, 118.8, 123.0, 127.3, 131.8, 136.5, 141.3, 146.2, 151.4, 156.7,
  162.2, 167.9, 173.8, 179.9, 186.2, 192.8, 203.5, 210.7, 218.1, 225.7, 233.6, 241.8, 250.3,
  1750
};

const char* tmv7_init_sequence[] = {
  "RX",
  "SC 0,0",
  "SC 1,0",
  "SM 0",
  "PC 0",
  "VMC 0",
  "MC 0",
  "BUF 0",
  "SM 1",
  "PC 1",
  "VMC 1",
  "MC 1",
  "BUF 1",
  "BC",
  "AI 1",
  "THE_END"
};

const byte max_fifo_depth = 9;
const byte max_fifo_pointer = 10;

char Str_tmv7_cmd_fifo[CMD_FIFO_SIZE][STR_SIZE];
char Str_tmv7_par_fifo[PAR_FIFO_SIZE][51];
char Str_tmv7_cmd_fifo_pointer;
unsigned char Byt_tmv7_fifo_input_pointer;
unsigned char Byt_tmv7_fifo_parse_pointer;
unsigned char Byt_tmv7_fifo_depth;
unsigned char Byt_tmv7_cmd_par_mode;

unsigned char Byt_tmv7_received_char;
char Str_dummy[21];
unsigned char Byt_dummy;

char Str_tmv7_freq[3][16];
char Str_tmv7_shift[3][13];
char Str_tmv7_vmc_mode[3][5];
char Str_tmv7_power_control[3][4];
char Str_tmv7_paging_control[3][2];
char Str_tmv7_signal_level[3][10];
char Str_tmv7_busy_status[3][2];
char Str_tmv7_tone_mode[3][3];
char Str_tmv7_reverse_mode[3][2];
unsigned char Byt_tmv7_tone_value[3];

char Str_tmv7_ai_str[2];
char Str_tmv7_id_str[6];
char Str_tmv7_par_str[51];

char Str_tmv7_ptt_status[2];
unsigned char Byt_tmv7_transmit_band;
unsigned char Byt_tmv7_control_band;
unsigned char Byt_tmv7_message_band;

Byt_tmv7_received_char = 0;

Str_dummy[0] = '\0';
Byt_dummy = 0;

Str_tmv7_freq[1][0] = '\0';
Str_tmv7_shift[1][0] = '\0';
strcpy(Str_tmv7_vmc_mode[1], "0");
strcpy(Str_tmv7_power_control[1], " ");
strcpy(Str_tmv7_paging_control[1], " ");
Str_tmv7_signal_level[1][0] = '\0';
Str_tmv7_busy_status[1][0] = '\0';
strcpy(Str_tmv7_tone_mode[1], "  ");
Str_tmv7_reverse_mode[1][0] = '\0';
Byt_tmv7_tone_value[1] = 0;

Str_tmv7_freq[2][0] = '\0';
Str_tmv7_shift[2][0] = '\0';
strcpy(Str_tmv7_vmc_mode[2], "0");
strcpy(Str_tmv7_power_control[2], " ");
strcpy(Str_tmv7_paging_control[2], " ");
Str_tmv7_signal_level[2][0] = '\0';
Str_tmv7_busy_status[2][0] = '\0';
strcpy(Str_tmv7_tone_mode[2], "  ");
Str_tmv7_reverse_mode[2][0] = '\0';
Byt_tmv7_tone_value[2] = 0;

Str_tmv7_ai_str[0] = '\0';
strcpy(Str_tmv7_id_str, "unkwn");
Str_tmv7_par_str[0] = '\0';

strcpy(Str_tmv7_ptt_status, "?");
Byt_tmv7_transmit_band = 0;
Byt_tmv7_control_band = 0;
Byt_tmv7_message_band = 0;

for (Byt_tmv7_fifo_input_pointer = 1; Byt_tmv7_fifo_input_pointer <= 10; Byt_tmv7_fifo_input_pointer++) {
    Str_tmv7_cmd_fifo[Byt_tmv7_fifo_input_pointer - 1][0] = '\0';
    Str_tmv7_par_fifo[Byt_tmv7_fifo_input_pointer - 1][0] = '\0';
}

Byt_tmv7_fifo_input_pointer = 1;
Byt_tmv7_fifo_parse_pointer = 1;
Byt_tmv7_cmd_par_mode = 0;
Byt_tmv7_fifo_depth = 0;


// Define custom characters for the LCD
const uint8_t custom_chars[8][8] = {
    {0x00, 0x1F, 0x11, 0x15, 0x11, 0x17, 0x17, 0x1F}, // Inverse "P" - PTT band marker
    {0x00, 0x1F, 0x11, 0x17, 0x17, 0x17, 0x11, 0x1F}, // Inverse "C" - CTRL band marker
    {0x00, 0x1F, 0x13, 0x11, 0x11, 0x11, 0x13, 0x1F}, // Inverse "D" - DTSS indicator
    {0x00, 0x1F, 0x11, 0x15, 0x11, 0x13, 0x15, 0x1F}, // Inverse "R" - Reverse shift marker
    {0x00, 0x1F, 0x11, 0x1B, 0x1B, 0x1B, 0x1B, 0x1F}, // Inverse "T" - CTCSS marker
    {0x20, 0x20, 0x20, 0x20, 0x20, 0x1F, 0x1F, 0x20}, // Bargraph 1
    {0x20, 0x20, 0x20, 0x20, 0x1F, 0x1F, 0x1F, 0x20}, // Bargraph 2
    {0x20, 0x20, 0x20, 0x1F, 0x1F, 0x1F, 0x1F, 0x20}  // Bargraph 3
};

// Initialize the LCD
void lcd_init() {
    // Set up the LCD pins
    // ...

    // Set up the LCD control registers
    // ...

    // Define custom characters
    for (uint8_t i = 0; i < 8; i++) {
        lcd_command(0x40 + i * 8);
        for (uint8_t j = 0; j < 8; j++) {
            lcd_data(custom_chars[i][j]);
        }
    }

    // Clear the LCD
    lcd_command(1);

    // Turn off the cursor and blinking
    lcd_command(0x0C);

    // Wait for the LCD voltages to settle
    _delay_ms(100);
}

int main() {
    lcd_init();
    Serial.begin(9600);

    // Display some information on the LCD
    lcd_gotoxy(0, 0);
    lcd_puts("TM-V7 LCD Vers. 1.06");
    lcd_gotoxy(0, 1);
    lcd_puts("ATmega8, 9k6, Int.RC");
    lcd_gotoxy(0, 2);
    lcd_puts("(c) 04/2009 OE9MKV");
    lcd_gotoxy(0, 3);
    lcd_puts("Transceiver:");
    lcd_gotoxy(15, 3);
    
    // Tell the transceiver to be quiet
    serial_write("AI 0\r");
    _delay_ms(50);

    serial_write("AI 0\r");
    _delay_ms(50);

    // Identify the transceiver model
    serial_write("ID\r");
    _delay_ms(250);

    serial_write("ID\r");
    _delay_ms(250);

    // Analyze the transceiver's answers
    parse_messages();
    lcd_puts(Str_tmv7_id_str);
    _delay_ms(2000);

    // Start transceiver initialization sequence
    lcd_gotoxy(3, 0);
    lcd_puts("Init:");
    lcd_gotoxy(3, 1);

    while (1) {
        char str_dummy[16];
        read_init_sequence(str_dummy);

        if (strcmp(str_dummy, "THE_END") == 0) {
            break;
        }

        serial_write(str_dummy);
        lcd_putc(255);
        _delay_ms(100);
        parse_messages();
    }

    while (1) {
        parse_messages();

        // Display all parameters for band 0
        lcd_gotoxy(0, 0);
        lcd_puts(left(str_tmv7_vmc_mode[0], 3));
        lcd_puts(" ");

        lcd_gotoxy(0, 3);
        lcd_puts(" ");

        if (strcmp(str_tmv7_busy_status[0], "1") == 0) {
            lcd_puts(left(str_tmv7_signal_level[0], 8));
        } else if (str_tmv7_ptt_status == 'T' && byt_tmv7_transmit_band == 0) {
            lcd_puts(left(str_tmv7_signal_level[0], 8));
        } else if (strcmp(str_tmv7_tone_mode[0], "  ") != 0) {
            lcd_puts("   ");
            char* str_dummy = lookup_str(byt_tmv7_tone_value[0], Lbl_ctcss_values);
            lcd_puts(left(str_dummy, 5));
            lcd_puts("  ");
        } else {
            lcd_puts("        ");
        }

        lcd_gotoxy(0, 12);
        lcd_puts(" ");
        lcd_puts(left(str_tmv7_reverse_mode[0], 1));
        lcd_puts(left(str_tmv7_paging_control[0], 1));
        lcd_puts(left(str_tmv7_tone_mode[0], 2));
        lcd_puts(" ");

        lcd_gotoxy(0, 17);
        if (byt_tmv7_control_band == 0) {
            lcd_puts(" ");
            lcd_puts(0x01);
        } else {
            lcd_puts("  ");
        }

        lcd_gotoxy(0, 19);
        if (byt_tmv7_transmit_band == 0) {
            lcd_puts(0);
        } else {
            lcd_puts(" ");
        }

        // Display all parameters for band 1
        lcd_gotoxy(2, 0);
        lcd_puts(left(str_tmv7_vmc_mode[1], 3));
        lcd_puts(" ");

        lcd_gotoxy(2, 3);
        lcd_puts(" ");

        if (strcmp(str_tmv7_busy_status[1], "1") == 0) {
            lcd_puts(left(str_tmv7_signal_level[1], 8));
        } else if (str_tmv7_ptt_status == 'T' && byt_tmv7_transmit_band == 1) {
            lcd_puts(left(str_tmv7_signal_level[1], 8));
        } else if (strcmp(str_tmv7_tone_mode[1], "  ") != 0) {
            lcd_puts("   ");
            char* str_dummy = lookup_str(byt_tmv7_tone_value[1], Lbl_ctcss_values);
            lcd_puts(left(str_dummy, 5));
            lcd_puts("  ");
        } else {
            lcd_puts("        ");
        }

        lcd_gotoxy(2, 12);
        lcd_puts(" ");
        lcd_puts(left(str_tmv7_reverse_mode[1], 1));
        lcd_puts(left(str_tmv7_paging_control[1], 1));
        lcd_puts(left(str_tmv7_tone_mode[1], 2));
        lcd_puts(" ");

        lcd_gotoxy(2, 17);
        if (byt_tmv7_control_band == 1) {
            lcd_puts(" ");
            lcd_puts(0x01);
        } else {
            lcd_puts("  ");
        }

        lcd_gotoxy(2, 19);
        if (byt_tmv7_transmit_band == 1) {
            lcd_puts(0);
        } else {
            lcd_puts(" ");
        }

        // Display other parameters for both bands
        lcd_gotoxy(3, 0);
        lcd_puts(left(str_tmv7_power_control[1], 1));
        lcd_puts(" ");

        lcd_gotoxy(3, 3);
        lcd_puts(left(str_tmv7_freq[1], 10));
        lcd_puts(" ");

        lcd_gotoxy(3, 13);
        lcd_puts(" ");
        lcd_puts(left(str_tmv7_shift[1], 6));

        lcd_gotoxy(4, 0);
        lcd_puts(left(str_tmv7_power_control[2], 1));
        lcd_puts(" ");

        lcd_gotoxy(4, 3);
        lcd_puts(left(str_tmv7_freq[2], 10));
        lcd_puts(" ");

        lcd_gotoxy(4, 13);
        lcd_puts(" ");
        lcd_puts(left(str_tmv7_shift[2], 6));
    }

    return 0;
}

void read_init_sequence(char* str_dummy) {
    // Read the next line from the initialization sequence
    // and copy it to str_dummy
    // ...

    // Handle Serial.read() logic - TBA
}

void tmv7Init() {
  for (int i = 0; i < sizeof(tmv7_init_sequence) / sizeof(tmv7_init_sequence[0]); i++) {
    Serial.println(tmv7_init_sequence[i]);
    delay(50);
  }
}

void parseMessages() {
  while (byt_tmv7_fifo_depth > 0) {
    switch (str_tmv7_cmd_fifo[byt_tmv7_fifo_parse_pointer]) {
      case '?':
      case 'N':
      case 'E':
        // Error, do nothing
        break;
      case 'RX':
        str_tmv7_ptt_status = "R";
        break;
      case 'TX':
        str_tmv7_ptt_status = "T";
        break;
      case 'TT':
        str_tmv7_ptt_status = "!";
        break;
      case 'ID':
        str_tmv7_id_str = str_tmv7_par_fifo[byt_tmv7_fifo_parse_pointer];
        break;
      case 'AI':
        str_tmv7_ai_str = str_tmv7_par_fifo[byt_tmv7_fifo_parse_pointer];
        break;
      case 'VMC': {
        String str_tmv7_par_str = str_tmv7_par_fifo[byt_tmv7_fifo_parse_pointer];
        if (str_tmv7_par_str.length() == 3) {
          String str_dummy = str_tmv7_par_str.substring(0, 1);
          byte byt_tmv7_message_band = str_dummy.toInt();
          str_dummy = str_tmv7_par_str.substring(2, 3);
          byte byt_dummy = str_dummy.toInt();
          String str_vmc_mode;
          switch (byt_dummy) {
            case 0:
              str_vmc_mode = "[V]";
              break;
            case 3:
              str_vmc_mode = "[C]";
              break;
          }
          str_tmv7_vmc_mode[byt_tmv7_message_band + 1] = str_vmc_mode;
        }
        break;
      }
      case 'MC': {
        String str_tmv7_par_str = str_tmv7_par_fifo[byt_tmv7_fifo_parse_pointer];
        if (str_tmv7_par_str.length() == 4) {
          str_tmv7_par_str += " ";
          String str_dummy = str_tmv7_par_str.substring(0, 1);
          byte byt_tmv7_message_band = str_dummy.toInt();
          str_tmv7_vmc_mode[byt_tmv7_message_band + 1] = str_tmv7_par_str.substring(3, 6);
        }
        break;
      }
      case 'BC': {
        String str_tmv7_par_str = str_tmv7_par_fifo[byt_tmv7_fifo_parse_pointer];
        if (str_tmv7_par_str.length() == 3) {
          String str_dummy = str_tmv7_par_str.substring(0, 1);
          byt_tmv7_control_band = str_dummy.toInt();
          str_dummy = str_tmv7_par_str.substring(2, 3);
          byt_tmv7_transmit_band = str_dummy.toInt();
        }
        break;
      }
      case 'PC': {
        String str_tmv7_par_str = str_tmv7_par_fifo[byt_tmv7_fifo_parse_pointer];
        if (str_tmv7_par_str.length() == 3) {
          String str_dummy = str_tmv7_par_str.substring(0, 1);
          byte byt_tmv7_message_band = str_dummy.toInt();
          str_dummy = str_tmv7_par_str.substring(2, 3);
          byte byt_dummy = str_dummy.toInt();
          String str_power_control;
          switch (byt_dummy) {
            case 0:
              str_power_control = "H";
              break;
            case 1:
              str_power_control = "M";
              break;
            case 2:
              str_power_control = "L";
              break;
          }
          str_tmv7_power_control[byt_tmv7_message_band + 1] = str_power_control;
        }
        break;
      }
      case 'PG': {
        String str_tmv7_par_str = str_tmv7_par_fifo[byt_tmv7_fifo_parse_pointer];
        if (str_tmv7_par_str.length() == 3) {
          String str_dummy = str_tmv7_par_str.substring(0, 1);
          byte byt_tmv7_message_band = str_dummy.toInt();
          str_dummy = str_tmv7_par_str.substring(2, 3);
          byte byt_dummy = str_dummy.toInt();
          String str_pg_level;
          switch (byt_dummy) {
            case 0:
              str_pg_level = "H";
              break;
            case 1:
              str_pg_level = "M";
              break;
            case 2:
              str_pg_level = "L";
              break;
          }
          str_tmv7_pg_level[byt_tmv7_message_band + 1] = str_pg_level;
        }
        break;
      }
    }
    byt_tmv7_fifo_parse_pointer++;
    byt_tmv7_fifo_depth--;
  }
}

void isrCharReceived() {
  byte byt_tmv7_received_char = Serial.read();

  switch (byt_tmv7_received_char) {
    case 32:
      byt_tmv7_cmd_par_mode = 1;
      break;
    case 13:
      byt_tmv7_fifo_input_pointer++;
      if (byt_tmv7_fifo_input_pointer > Con_max_fifo_pointer) {
        byt_tmv7_fifo_input_pointer = 1;
      }
      byt_tmv7_fifo_depth++;
      if (byt_tmv7_fifo_depth > Con_max_fifo_depth) {
        byt_tmv7_fifo_depth = Con_max_fifo_depth;
      }
      byt_tmv7_cmd_par_mode = 0;
      break;
    default:
      if (byt_tmv7_cmd_par_mode == 0) {
        str_tmv7_cmd_fifo[byt_tmv7_fifo_input_pointer] += (char) byt_tmv7_received_char;
      } else {
        str_tmv7_par_fifo[byt_tmv7_fifo_input_pointer] += (char) byt_tmv7_received_char;
      }
      break;
  }
}
