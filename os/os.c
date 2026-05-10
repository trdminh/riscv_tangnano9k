#include "os_config.h"

#define CHAR_BACKSPACE 0x7f
#define CHAR_CARRIAGE_RETURN 0x0d
#define LOCATION_MAX_OBJECTS 128
#define LOCATION_MAX_ENTITIES 8
#define LOCATION_MAX_EXITS 6
#define ENTITY_MAX_OBJECTS 32
#define TRUE 1
#define FALSE 0

// BMP280 registers and constants
#define BMP280_ADDR 0x76
#define BMP280_REG_ID 0xD0
#define BMP280_REG_CTRL_MEAS 0xF4
#define BMP280_REG_PRESS_MSB 0xF7
#define BMP280_REG_TEMP_MSB 0xFA
#define BMP280_ID 0x58

void uart_send_str(const char *str);
void uart_send_char(char ch);
char uart_read_char();
void uart_send_hex_byte(char ch);
void uart_send_hex_nibble(char nibble);
void i2c_send(unsigned char data);
unsigned char i2c_read(unsigned char reg_addr);
unsigned char i2c_is_busy();
unsigned char i2c_is_done();
void bmp280_init();
void bmp280_read_temp();
void delay_ms(unsigned int ms);

typedef const char *name;
typedef unsigned char location_id;
typedef unsigned char object_id;
typedef unsigned char entity_id;
typedef unsigned char direction;

static char *hello = "welcome to adventure #4\r\n    type 'help'\r\n\r\n";

typedef struct input_buffer {
  char line[80];
  unsigned char ix;
} input_buffer;

typedef struct object {
  name name;
} object;

static object objects[] = {{""}, {"notebook"}, {"mirror"}, {"lighter"}};

typedef struct entity {
  name name;
  location_id location;
  object_id objects[ENTITY_MAX_OBJECTS];
} entity;

static entity entities[] = {{"", 0, {0}}, {"me", 1, {2}}, {"u", 2, {0}}};

typedef struct location {
  name name;
  object_id objects[LOCATION_MAX_OBJECTS];
  entity_id entities[LOCATION_MAX_ENTITIES];
  location_id exits[LOCATION_MAX_EXITS];
} location;

static location locations[] = {{"", {0}, {0}, {0}},
                               {"roome", {0}, {1}, {2, 3, 0, 4}},
                               {"office", {1, 3}, {2}, {0, 0, 1}},
                               {"bathroom", {0}, {0}, {0}},
                               {"kitchen", {0}, {0}, {0, 1}}};

static const char *exit_names[] = {"north", "east", "south",
                                   "west",  "up",   "down"};

void print_help();
void print_location(location_id lid, entity_id eid_exclude_from_output);
unsigned char add_object_to_list(object_id list[], unsigned list_len, object_id oid);
void remove_object_from_list_by_index(object_id list[], unsigned ix);
unsigned char add_entity_to_list(entity_id list[], unsigned list_len, entity_id eid);
void remove_entity_from_list_by_index(entity_id list[], unsigned ix);
void remove_entity_from_list(entity_id list[], unsigned list_len,
                             entity_id eid);
void action_inventory(entity_id eid);
void action_give(entity_id eid, name obj, name to_ent);
void action_go(entity_id eid, direction dir);
void action_drop(entity_id eid, name obj);
void action_take(entity_id eid, name obj);
void input(input_buffer *buf);
void handle_input(entity_id eid, input_buffer *buf);
unsigned char strings_equal(const char *s1, const char *s2);

void run() {
  *leds = 0xe;

  uart_send_str("=== RISC-V System with BMP280 ===\r\n");

  bmp280_init();
  input_buffer inbuf;
  inbuf.ix = 0;

  uart_send_str(hello);

  *leds = 0xd;

  while (1) {
    input(&inbuf);
    uart_send_str("\r\n");
    bmp280_read_temp();
}

void handle_input(entity_id eid, input_buffer *buf) {
  const char *words[8];
  char *ptr = buf->line;
  unsigned nwords = 0;
  while (1) {
    words[nwords++] = ptr;
    while (*ptr && *ptr != ' ') {
      ptr++;
    }
    if (!*ptr)
      break;
    *ptr = 0;
    ptr++;
    if (nwords == sizeof(words) / sizeof(const char *)) {
      uart_send_str("too many words, some ignored\r\n\r\n");
      break;
    }
  }
  //  for (unsigned i = 0; i < nwords; i++) {
  //    uart_send_str(words[i]);
  //    uart_send_str("\r\n");
  //  }
  if (strings_equal(words[0], "help")) {
    print_help();
  } else if (strings_equal(words[0], "i")) {
    action_inventory(eid);
    uart_send_str("\r\n");
  } else if (strings_equal(words[0], "t")) {
    if (nwords < 2) {
      uart_send_str("take what\r\n\r\n");
      return;
    }
    action_take(eid, words[1]);
  } else if (strings_equal(words[0], "d")) {
    if (nwords < 2) {
      uart_send_str("drop what\r\n\r\n");
      return;
    }
    action_drop(eid, words[1]);
  } else if (strings_equal(words[0], "n")) {
    action_go(eid, 0);
  } else if (strings_equal(words[0], "e")) {
    action_go(eid, 1);
  } else if (strings_equal(words[0], "s")) {
    action_go(eid, 2);
  } else if (strings_equal(words[0], "w")) {
    action_go(eid, 3);
  } else if (strings_equal(words[0], "g")) {
    if (nwords < 2) {
      uart_send_str("give what\r\n\r\n");
      return;
    }
    if (nwords < 3) {
      uart_send_str("give to whom\r\n\r\n");
      return;
    }
    action_give(eid, words[1], words[2]);
  } else if (strings_equal(words[0], "sensor")) {
    bmp280_read_temp();
    uart_send_str("\r\n");
  } else {
    uart_send_str("not understood\r\n\r\n");
  }
}

void print_location(location_id lid, entity_id eid_exclude_from_output) {
  const location *loc = &locations[lid];
  uart_send_str("u r in ");
  uart_send_str(loc->name);
  uart_send_str("\r\nu c: ");

  // print objects in location
  unsigned char add_list_sep = FALSE;
  const object_id *lso = loc->objects;
  for (unsigned i = 0; i < LOCATION_MAX_OBJECTS; i++) {
    const object_id oid = lso[i];
    if (!oid)
      break;
    if (add_list_sep) {
      uart_send_str(", ");
    } else {
      add_list_sep = TRUE;
    }
    uart_send_str(objects[oid].name);
  }
  if (!add_list_sep) {
    uart_send_str("nothing");
  }
  uart_send_str("\r\n");

  // print entities in location
  add_list_sep = FALSE;
  const entity_id *lse = loc->entities;
  for (unsigned i = 0; i < LOCATION_MAX_ENTITIES; i++) {
    const entity_id eid = lse[i];
    if (!eid)
      break;
    if (eid == eid_exclude_from_output)
      continue;
    if (add_list_sep) {
      uart_send_str(", ");
    } else {
      add_list_sep = TRUE;
    }
    uart_send_str(entities[eid].name);
  }
  if (add_list_sep) {
    uart_send_str(" is here\r\n");
  }

  // print exits from location
  add_list_sep = FALSE;
  uart_send_str("exits: ");
  for (unsigned i = 0; i < LOCATION_MAX_EXITS; i++) {
    if (!loc->exits[i])
      continue;
    if (add_list_sep) {
      uart_send_str(", ");
    } else {
      add_list_sep = TRUE;
    }
    uart_send_str(exit_names[i]);
  }
  if (!add_list_sep) {
    uart_send_str("none");
  }
  uart_send_str("\r\n");
}

void action_inventory(entity_id eid) {
  uart_send_str("u have: ");
  unsigned char add_list_sep = FALSE;
  const object_id *lso = entities[eid].objects;
  for (unsigned i = 0; i < ENTITY_MAX_OBJECTS; i++) {
    const object_id oid = lso[i];
    if (!oid)
      break;
    if (add_list_sep) {
      uart_send_str(", ");
    } else {
      add_list_sep = TRUE;
    }
    uart_send_str(objects[oid].name);
  }
  if (!add_list_sep) {
    uart_send_str("nothing");
  }
  uart_send_str("\r\n");
}

void remove_object_from_list_by_index(object_id list[], unsigned ix) {
  object_id *ptr = &list[ix];
  while (1) {
    *ptr = *(ptr + 1);
    if (!*ptr)
      return;
    ptr++;
  }
}

unsigned char add_object_to_list(object_id list[], unsigned list_len, object_id oid) {
  // list_len - 1 since last element has to be 0
  for (unsigned i = 0; i < list_len - 1; i++) {
    if (list[i])
      continue;
    list[i] = oid;
    list[i + 1] = 0;
    return TRUE;
  }
  uart_send_str("space full\r\n");
  return FALSE;
}

unsigned char add_entity_to_list(entity_id list[], unsigned list_len, entity_id eid) {
  // list_len - 1 since last element has to be 0
  for (unsigned i = 0; i < list_len - 1; i++) {
    if (list[i])
      continue;
    list[i] = eid;
    list[i + 1] = 0;
    return TRUE;
  }
  uart_send_str("location full\r\n");
  return FALSE;
}

void remove_entity_from_list(entity_id list[], unsigned list_len,
                             entity_id eid) {
  // list_len - 1 since last element has to be 0
  for (unsigned i = 0; i < list_len - 1; i++) {
    if (list[i] != eid)
      continue;
    // list_len - 1 since last element has to be 0
    for (unsigned j = i; j < list_len - 1; j++) {
      list[j] = list[j + 1];
      if (!list[j])
        return;
    }
  }
  uart_send_str("entity not here\r\n");
}

void remove_entity_from_list_by_index(entity_id list[], unsigned ix) {
  entity_id *ptr = &list[ix];
  while (1) {
    *ptr = *(ptr + 1);
    if (!*ptr)
      return;
    ptr++;
  }
}

void action_take(entity_id eid, name obj) {
  entity *ent = &entities[eid];
  object_id *lso = locations[ent->location].objects;
  for (unsigned i = 0; i < LOCATION_MAX_OBJECTS; i++) {
    const object_id oid = lso[i];
    if (!oid)
      break;
    if (!strings_equal(objects[oid].name, obj))
      continue;
    if (add_object_to_list(ent->objects, ENTITY_MAX_OBJECTS, oid)) {
      remove_object_from_list_by_index(lso, i);
    }
    return;
  }
  uart_send_str(obj);
  uart_send_str(" not here\r\n\r\n");
}

void action_drop(entity_id eid, name obj) {
  entity *ent = &entities[eid];
  object_id *lso = ent->objects;
  for (unsigned i = 0; i < ENTITY_MAX_OBJECTS; i++) {
    const object_id oid = lso[i];
    if (!oid)
      break;
    if (!strings_equal(objects[oid].name, obj))
      continue;
    if (add_object_to_list(locations[ent->location].objects,
                           LOCATION_MAX_OBJECTS, oid)) {
      remove_object_from_list_by_index(lso, i);
    }
    return;
  }
  uart_send_str("u don't have ");
  uart_send_str(obj);
  uart_send_str("\r\n\r\n");
}

void action_go(entity_id eid, direction dir) {
  entity *ent = &entities[eid];
  location *loc = &locations[ent->location];
  const location_id to = loc->exits[dir];
  if (!to) {
    uart_send_str("cannot go there\r\n\r\n");
    return;
  }
  if (add_entity_to_list(locations[to].entities, LOCATION_MAX_ENTITIES, eid)) {
    remove_entity_from_list(loc->entities, LOCATION_MAX_ENTITIES, eid);
    ent->location = to;
  }
}

void action_give(entity_id eid, name obj, name to_ent) {
  entity *ent = &entities[eid];
  const location *loc = &locations[ent->location];
  const entity_id *lse = loc->entities;
  for (unsigned i = 0; i < LOCATION_MAX_ENTITIES; i++) {
    if (!lse[i])
      break;
    entity *to = &entities[lse[i]];
    if (!strings_equal(to->name, to_ent))
      continue;
    object_id *lso = ent->objects;
    for (unsigned j = 0; j < ENTITY_MAX_OBJECTS; j++) {
      const object_id oid = lso[j];
      if (!oid)
        break;
      if (!strings_equal(objects[oid].name, obj))
        continue;
      if (add_object_to_list(to->objects, ENTITY_MAX_OBJECTS, oid)) {
        remove_object_from_list_by_index(lso, j);
      }
      return;
    }
    uart_send_str(obj);
    uart_send_str(" not in inventory\r\n\r\n");
    return;
  }
  uart_send_str(to_ent);
  uart_send_str(" is not here\r\n\r\n");
}

void print_help() {
  uart_send_str(
      "\r\ncommand:\r\n  n: go north\r\n  e: go east\r\n  s: go south\r\n  w: "
      "go west\r\n  i: "
      "display inventory\r\n  t <object>: take object\r\n  d <object>: drop "
      "object\r\n  g <object> <entity>: give object to entity\r\n  sensor: read BMP280\r\n  help: this "
      "message\r\n\r\n");
}

void input(input_buffer *buf) {
  while (1) {
    const char ch = uart_read_char();
    if (ch == CHAR_BACKSPACE) {
      if (buf->ix > 0) {
        buf->ix--;
        uart_send_char(ch);
      }
    } else if (ch == CHAR_CARRIAGE_RETURN ||
               buf->ix ==
                   sizeof(buf->line) - 1) { // -1 since last char must be 0
      buf->line[buf->ix] = 0;
      buf->ix = 0;
      return;
    } else {
      buf->line[buf->ix] = ch;
      buf->ix++;
      uart_send_char(ch);
    }
    *leds = ~buf->ix;
  }
}

unsigned char strings_equal(const char *s1, const char *s2) {
  while (1) {
    if (*s1 - *s2)
      return FALSE;
    if (!*s1 && !*s2)
      return TRUE;
    s1++;
    s2++;
  }
}

void uart_send_str(const char *str) {
  while (*str) {
    while (*uart_out)
      ;
    *uart_out = *str++;
  }
}

void uart_send_hex_byte(const char ch) {
  uart_send_hex_nibble((ch & 0xf0) >> 4);
  uart_send_hex_nibble(ch & 0x0f);
}

void uart_send_hex_nibble(const char nibble) {
  if (nibble < 10) {
    uart_send_char('0' + nibble);
  } else {
    uart_send_char('A' + (nibble - 10));
  }
}

void uart_send_char(const char ch) {
  while (*uart_out)
    ;
  *uart_out = ch;
}

void print_int(int num) {
  unsigned char digits[12];
  int len = 0;

  if (num == 0) {
    uart_send_char('0');
    return;
  }

  if (num < 0) {
    uart_send_char('-');
    num = -num;
  }

  unsigned int n = (unsigned int)num;
  while (n > 0) {
    digits[len++] = '0' + (n % 10);
    n = n / 10;
  }

  while (len > 0) {
    uart_send_char(digits[--len]);
  }
}

char uart_read_char() {
  char ch;
  while ((ch = *uart_in) == 0)
    ;
  return ch;
}

void i2c_send(unsigned char data) {
  *i2c_data = data;
  *i2c_ctrl = 0x01;
  while (i2c_is_busy());
}

unsigned char i2c_read(unsigned char reg_addr) {
  *i2c_data = reg_addr;
  *i2c_ctrl = 0x01;
  while (i2c_is_busy());

  *i2c_ctrl = 0x03;
  while (i2c_is_busy());

  return *i2c_data;
}

unsigned char i2c_is_busy() {
  return (*i2c_ctrl & 0x01);
}

unsigned char i2c_is_done() {
  return (*i2c_ctrl & 0x02) >> 1;
}

void delay_ms(unsigned int ms) {
  volatile unsigned int i, j;
  for (i = 0; i < ms; i++)
    for (j = 0; j < 1000; j++);
}

void bmp280_init() {
  uart_send_str("Initializing BMP280...\r\n");

  uart_send_str("BMP280 Address: 0x");
  uart_send_hex_byte(BMP280_ADDR << 1);
  uart_send_str("\r\n");

  i2c_send(BMP280_REG_CTRL_MEAS);
  delay_ms(10);
  i2c_send(0x27);

  uart_send_str("BMP280 Initialized\r\n");
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

void bmp280_read_temp() {
  uart_send_str("=== BMP280 Sensor Reading ===\r\n");

  uart_send_str("Sensor Address: 0x");
  uart_send_hex_byte(BMP280_ADDR);
  uart_send_str("\r\n\r\n");

  unsigned char temp_msb = i2c_read(BMP280_REG_TEMP_MSB);
  delay_ms(10);
  unsigned char temp_lsb = i2c_read(BMP280_REG_TEMP_MSB + 1);
  delay_ms(10);
  unsigned char temp_xlsb = i2c_read(BMP280_REG_TEMP_MSB + 2);
  delay_ms(10);

  int adc_temp = ((int)temp_msb << 12) | ((int)temp_lsb << 4) | ((int)temp_xlsb >> 4);

  int temp_c = 25;
  if (adc_temp < 0x80000) {
    temp_c = (adc_temp >> 8);
  } else {
    temp_c = -((0x100000 - adc_temp) >> 8);
  }

  int temp_val = (temp_c * 100) + ((adc_temp & 0xFF) / 2);

  uart_send_str("Raw ADC: 0x");
  uart_send_hex_byte((adc_temp >> 16) & 0xFF);
  uart_send_hex_byte((adc_temp >> 8) & 0xFF);
  uart_send_hex_byte(adc_temp & 0xFF);
  uart_send_str("\r\n");

  print_temperature(temp_val);

  unsigned char press_msb = i2c_read(BMP280_REG_PRESS_MSB);
  delay_ms(10);
  unsigned char press_lsb = i2c_read(BMP280_REG_PRESS_MSB + 1);
  delay_ms(10);
  unsigned char press_xlsb = i2c_read(BMP280_REG_PRESS_MSB + 2);
  delay_ms(10);

  int adc_press = ((int)press_msb << 12) | ((int)press_lsb << 4) | ((int)press_xlsb >> 4);

  int pressure = 101325 + ((adc_press - 0x80000) / 100);

  uart_send_str("Pressure: ");
  print_int(pressure / 100);
  uart_send_str(".");
  print_int(pressure % 100);
  uart_send_str(" hPa\r\n");

  uart_send_str("\r\nStatus: BMP280 Ready\r\n");
}
