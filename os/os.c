#include "os_config.h"

#define CHAR_BACKSPACE        0x7f
#define CHAR_CARRIAGE_RETURN  0x0d

#define BMP280_ADDR           0x76

#define BMP280_REG_ID         0xD0
#define BMP280_REG_RESET      0xE0
#define BMP280_REG_STATUS     0xF3
#define BMP280_REG_CTRL_MEAS  0xF4
#define BMP280_REG_CONFIG     0xF5

#define BMP280_REG_PRESS_MSB  0xF7
#define BMP280_REG_TEMP_MSB   0xFA

#define BMP280_ID             0x58

#define TRUE  1
#define FALSE 0

void uart_send_str(const char *str);
void uart_send_char(char ch);
char uart_read_char();

void uart_send_hex_byte(unsigned char ch);
void uart_send_hex_nibble(unsigned char nibble);

void print_int(int num);

void delay_ms(unsigned int ms);

/* =========================================================
   UART
========================================================= */

void uart_send_char(const char ch) {
    while (*uart_out);
    *uart_out = ch;
}

void uart_send_str(const char *str) {
    while (*str) {
        uart_send_char(*str++);
    }
}

char uart_read_char() {
    char ch;
    while ((ch = *uart_in) == 0);
    return ch;
}

void uart_send_hex_nibble(unsigned char nibble) {
    if (nibble < 10)
        uart_send_char('0' + nibble);
    else
        uart_send_char('A' + (nibble - 10));
}

void uart_send_hex_byte(unsigned char ch) {
    uart_send_hex_nibble((ch >> 4) & 0x0F);
    uart_send_hex_nibble(ch & 0x0F);
}

void print_int(int num) {
    char buf[12];
    int i = 0;

    if (num == 0) {
        uart_send_char('0');
        return;
    }

    if (num < 0) {
        uart_send_char('-');
        num = -num;
    }

    while (num > 0) {
        buf[i++] = '0' + (num % 10);
        num /= 10;
    }

    while (i > 0) {
        uart_send_char(buf[--i]);
    }
}

void delay_ms(unsigned int ms) {
    volatile unsigned int i, j;

    for (i = 0; i < ms; i++) {
        for (j = 0; j < 1000; j++);
    }
}

/* =========================================================
   LOW LEVEL I2C
========================================================= */

void i2c_wait() {
    while (*i2c_ctrl & 0x01);
}

void i2c_write_byte(unsigned char data) {
    *i2c_data = data;
    *i2c_ctrl = 0x01;

    i2c_wait();
}

unsigned char i2c_read_byte() {
    *i2c_ctrl = 0x03;

    i2c_wait();

    return *i2c_data;
}

/* =========================================================
   BMP280 DRIVER
========================================================= */

unsigned short dig_T1;
short dig_T2;
short dig_T3;

long t_fine;

/* ---------- Register Read/Write ---------- */

void bmp280_write_reg(unsigned char reg, unsigned char value) {

    /* slave addr + write */
    i2c_write_byte((BMP280_ADDR << 1) | 0);

    /* register */
    i2c_write_byte(reg);

    /* value */
    i2c_write_byte(value);
}

unsigned char bmp280_read_reg(unsigned char reg) {

    unsigned char value;

    /* write phase */
    i2c_write_byte((BMP280_ADDR << 1) | 0);

    i2c_write_byte(reg);

    /* read phase */
    i2c_write_byte((BMP280_ADDR << 1) | 1);

    value = i2c_read_byte();

    return value;
}

/* ---------- Calibration ---------- */

unsigned short bmp280_read16_LE(unsigned char reg) {

    unsigned char lsb;
    unsigned char msb;

    lsb = bmp280_read_reg(reg);
    msb = bmp280_read_reg(reg + 1);

    return ((unsigned short)msb << 8) | lsb;
}

short bmp280_readS16_LE(unsigned char reg) {
    return (short)bmp280_read16_LE(reg);
}

void bmp280_read_calibration() {

    dig_T1 = bmp280_read16_LE(0x88);
    dig_T2 = bmp280_readS16_LE(0x8A);
    dig_T3 = bmp280_readS16_LE(0x8C);

    uart_send_str("Calibration Loaded\r\n");
}

/* ---------- Init ---------- */

void bmp280_init() {

    uart_send_str("=== BMP280 INIT ===\r\n");

    unsigned char id;

    id = bmp280_read_reg(BMP280_REG_ID);

    uart_send_str("Chip ID: 0x");
    uart_send_hex_byte(id);
    uart_send_str("\r\n");

    if (id != BMP280_ID) {
        uart_send_str("BMP280 NOT FOUND\r\n");
        return;
    }

    uart_send_str("BMP280 DETECTED\r\n");

    bmp280_write_reg(BMP280_REG_CTRL_MEAS, 0x27);

    bmp280_write_reg(BMP280_REG_CONFIG, 0xA0);

    bmp280_read_calibration();

    uart_send_str("BMP280 READY\r\n\r\n");
}

/* ---------- Temperature ---------- */

long bmp280_read_raw_temp() {

    unsigned char msb;
    unsigned char lsb;
    unsigned char xlsb;

    long adc_T;

    msb  = bmp280_read_reg(BMP280_REG_TEMP_MSB);
    lsb  = bmp280_read_reg(BMP280_REG_TEMP_MSB + 1);
    xlsb = bmp280_read_reg(BMP280_REG_TEMP_MSB + 2);

    adc_T = ((long)msb << 12) |
            ((long)lsb << 4)  |
            ((long)xlsb >> 4);

    return adc_T;
}

long bmp280_compensate_temp(long adc_T) {

    long var1, var2, T;

    var1 = ((((adc_T >> 3) - ((long)dig_T1 << 1))) *
             ((long)dig_T2)) >> 11;

    var2 = (((((adc_T >> 4) - ((long)dig_T1)) *
              ((adc_T >> 4) - ((long)dig_T1))) >> 12) *
              ((long)dig_T3)) >> 14;

    t_fine = var1 + var2;

    T = (t_fine * 5 + 128) >> 8;

    return T;
}

void bmp280_print_temperature() {

    long raw_temp;
    long temp;

    raw_temp = bmp280_read_raw_temp();

    temp = bmp280_compensate_temp(raw_temp);

    uart_send_str("Raw Temp: 0x");

    uart_send_hex_byte((raw_temp >> 16) & 0xFF);
    uart_send_hex_byte((raw_temp >> 8) & 0xFF);
    uart_send_hex_byte(raw_temp & 0xFF);

    uart_send_str("\r\n");

    uart_send_str("Temperature: ");

    print_int(temp / 100);

    uart_send_char('.');

    if ((temp % 100) < 10)
        uart_send_char('0');

    print_int(temp % 100);

    uart_send_str(" C\r\n\r\n");
}

/* =========================================================
   MAIN
========================================================= */

void run() {

    *leds = 0x0F;

    uart_send_str("\r\n");
    uart_send_str("================================\r\n");
    uart_send_str(" RISC-V BMP280 DEMO\r\n");
    uart_send_str("================================\r\n\r\n");

    bmp280_init();

    while (1) {

        uart_send_str("Press ENTER to read sensor...\r\n");

        while (uart_read_char() != CHAR_CARRIAGE_RETURN);

        uart_send_str("\r\n");

        bmp280_print_temperature();

        delay_ms(1000);
    }
}