#include "os_config.h"

// BMP280 registers and constants
#define BMP280_ADDR 0x76
#define BMP280_REG_CTRL_MEAS 0xF4
#define BMP280_REG_TEMP_MSB 0xFA
#define BMP280_REG_PRESS_MSB 0xF7

void uart_send_str(const char *str);
void uart_send_char(char ch);
void uart_send_hex_byte(char ch);
void print_int(int num);
void i2c_send(unsigned char data);
unsigned char i2c_read(unsigned char reg_addr);
void delay_ms(unsigned int ms);

void bmp280_init();
void bmp280_read_temp();
void print_temperature(int temp_raw);

void bmp280_init() {
  uart_send_str("Initializing BMP280...\r\n");
  
  i2c_send(BMP280_REG_CTRL_MEAS);
  delay_ms(10);
  i2c_send(0x27);        // Normal mode, temperature and pressure oversampling x1

  uart_send_str("BMP280 Initialized\r\n\r\n");
}

void bmp280_read_temp() {
  uart_send_str("=== BMP280 Sensor Reading ===\r\n");

  // Đọc nhiệt độ
  unsigned char temp_msb = i2c_read(BMP280_REG_TEMP_MSB);
  delay_ms(5);
  unsigned char temp_lsb = i2c_read(BMP280_REG_TEMP_MSB + 1);
  delay_ms(5);
  unsigned char temp_xlsb = i2c_read(BMP280_REG_TEMP_MSB + 2);

  int adc_temp = ((int)temp_msb << 12) | ((int)temp_lsb << 4) | ((int)temp_xlsb >> 4);

  // Công thức đơn giản (không calibration - chỉ mang tính minh họa)
  int temp_c = 25;
  if (adc_temp < 0x80000) {
    temp_c = (adc_temp >> 8);
  } else {
    temp_c = -((0x100000 - adc_temp) >> 8);
  }

  int temp_val = (temp_c * 100) + ((adc_temp & 0xFF) / 2);

  // In thông tin
  uart_send_str("Raw ADC Temp: 0x");
  uart_send_hex_byte((adc_temp >> 16) & 0xFF);
  uart_send_hex_byte((adc_temp >> 8) & 0xFF);
  uart_send_hex_byte(adc_temp & 0xFF);
  uart_send_str("\r\n");

  print_temperature(temp_val);

  uart_send_str("\r\n");
}

void print_temperature(int temp_raw) {
  int temp_int = temp_raw / 100;
  int temp_frac = temp_raw % 100;

  uart_send_str("Temperature: ");
  print_int(temp_int);
  uart_send_char('.');
  if (temp_frac < 10) uart_send_char('0');
  print_int(temp_frac);
  uart_send_str(" C\r\n");
}

// Các hàm hỗ trợ cơ bản (giữ lại để code chạy được)
void uart_send_str(const char *str) {
  while (*str) {
    while (*uart_out);
    *uart_out = *str++;
  }
}

void uart_send_hex_byte(char ch) {
  uart_send_hex_nibble((ch & 0xf0) >> 4);
  uart_send_hex_nibble(ch & 0x0f);
}

void uart_send_hex_nibble(char nibble) {
  if (nibble < 10)
    uart_send_char('0' + nibble);
  else
    uart_send_char('A' + (nibble - 10));
}

void uart_send_char(char ch) {
  while (*uart_out);
  *uart_out = ch;
}

void print_int(int num) {
  if (num == 0) {
    uart_send_char('0');
    return;
  }
  if (num < 0) {
    uart_send_char('-');
    num = -num;
  }
  unsigned char digits[12];
  int len = 0;
  unsigned int n = (unsigned int)num;
  while (n > 0) {
    digits[len++] = '0' + (n % 10);
    n /= 10;
  }
  while (len > 0) {
    uart_send_char(digits[--len]);
  }
}

void i2c_send(unsigned char data) {
  *i2c_data = data;
  *i2c_ctrl = 0x01;
  while (*i2c_ctrl & 0x01);   // wait busy
}

unsigned char i2c_read(unsigned char reg_addr) {
  *i2c_data = reg_addr;
  *i2c_ctrl = 0x01;
  while (*i2c_ctrl & 0x01);

  *i2c_ctrl = 0x03;
  while (*i2c_ctrl & 0x01);

  return *i2c_data;
}

void delay_ms(unsigned int ms) {
  volatile unsigned int i, j;
  for (i = 0; i < ms; i++)
    for (j = 0; j < 1000; j++);
}

void run()
{
  bmp280_init();
  while(1) {
      bmp280_read_temp();
      delay_ms(1000);   // đọc mỗi giây
  }
}