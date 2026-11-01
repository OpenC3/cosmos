/*
 * message.h
 *
 * 
 * Created on: Oct 27, 2026
 *     Author: Alan
*/

#ifndef INC_MESSAGE_H_
#define INC_MESSAGE_H_

#include <stdint.h>

#define   PACKET_VERSION_BIT_LENGTH 3
#define   APID_BIT_LENGTH 11
#define   SEQUENCE_FLAG_BIT_LENGTH 2
#define   PACKET_SEQUENCE_COUNT_BIT_LENGTH 14

#define   MAX_DATA_LENGTH 65536

/** @defgroup Message ID structures (13 in size)
  * @{
  */
typedef enum
{
  MESSAGE_ID_DEFAULT                            = 0U,
  MESSAGE_ID_POWER_ON                           = 1U,
  MESSAGE_ID_ID_EXCHANCE                        = 2U,
  MESSAGE_ID_TIME                               = 3U,
  MESSAGE_ID_STATE                              = 4U,
  MESSAGE_ID_OFFSET                             = 5U,
  MESSAGE_ID_DO_BIT                             = 6U,
  MESSAGE_ID_BIT_COMPLETE_STATUS                = 7U,
  MESSAGE_ID_TELEMETRY_UPDATE                   = 15U,
  MESSAGE_ID_SHUTDOWN                           = 16U,
  MESSAGE_ID_START_FILE_TRANSFER                = 17U,
  MESSAGE_ID_FILE_TRANSFER_COMPLETE_STATUS      = 18U,
  MESSAGE_ID_RETURN_TO_IDLE                     = 19U,
  MESSAGE_ID_RESENT_LAST_RESPONSE               = 20U
  // Append more as you needed
} Message_IDTypeDef;
/**
  * @}
  */

typedef struct __attribute__((packed)){
  // First two octets of the primary header
  // APID length is not long enough 11 bits compared to 16 bits
  uint8_t packet_version:PACKET_VERSION_BIT_LENGTH;
  uint8_t packet_type_flag:1;
  uint8_t secondary_header_flag:1;
  uint16_t application_process_identifier:APID_BIT_LENGTH; //Might change to message_idtype def

  // Second two octets of the primary header
  uint8_t sequence_flags:SEQUENCE_FLAG_BIT_LENGTH;
  uint16_t packet_sequence_count:PACKET_SEQUENCE_COUNT_BIT_LENGTH;

  // Last two octets of the primary header
  uint16_t packet_data_length;
} message_header_t;

/* 
  Commented out since functions should not be the way we go because 
    each function will have to interact with a message struct that has changing
    size which is not the path forward
*/
// uint8_t create_power_up_message();
// uint8_t create_id_exchange_message();
// uint8_t create_time_message();
// uint8_t create_state_message();
// uint8_t create_offset_message();
// uint8_t create_do_bit_message();
// uint8_t create_bit_complete_status_message();
// uint8_t create_telemetry_update_message();
// uint8_t create_shutdown_message();
// uint8_t create_start_file_transfer_message();
// uint8_t create_file_transfer_complete_status_message();
// uint8_t create_return_to_idle_message();
// uint8_t create_resend_last_response_message();

/* 
  * ASSUMPTION: IF BITS MATCH THE TRANSLATION TO BYTES, WILL GO WITH THAT
*/
#define MESSAGE_IDENTITY_BYTE_SIZE 16
// #define SERIAL_NUMBER_BYTE_SIZE 16
// #define ID_TYPE_BYTE_SIZE 16
#define MESSAGE_SW_VERSION_BYTE_SIZE 4
typedef struct __attribute((packed)){
  uint8_t identity[MESSAGE_IDENTITY_BYTE_SIZE];
  // uint16_t serial_number[16];
  uint16_t serial_number;             // NEED CLARIFICATION
  uint16_t id_type;
  uint8_t sw_version[MESSAGE_SW_VERSION_BYTE_SIZE];
} id_exchange_message_t;

typedef struct __attribute((packed)){
  uint64_t timestamp;
  uint32_t uncertainty;
  uint16_t source;
} time_message_t;

typedef struct __attribute((packed)){
  uint64_t time_of_validity;
  uint16_t navigation_frame;
  double position_x;
  double position_y;
  double position_z;
  double velocity_x;
  double velocity_y;
  double velocity_z;
  double attitude_x;
  double attitude_y;
  double attitude_z;
  double attitude_scalar;
  double covariance_pos_x_pos_x;      // pos x
  double covariance_pos_x_pos_y;
  double covariance_pos_x_pos_z;
  double covariance_pos_x_vel_x;
  double covariance_pos_x_vel_y;
  double covariance_pos_x_vel_z;
  double covariance_pos_y_pos_y;      // pos y
  double covariance_pos_y_pos_z;
  double covariance_pos_y_vel_x;
  double covariance_pos_y_vel_y;
  double covariance_pos_y_vel_z;
  double covariance_pos_z_pos_z;      // pos z
  double covariance_pos_z_vel_x;
  double covariance_pos_z_vel_y;
  double covariance_pos_z_vel_z;
  double covariance_vel_x_vel_x;      // vel x
  double covariance_vel_x_vel_y;
  double covariance_vel_x_vel_z;
  // Below is commented out since not defined in ICD but will be here if that changes
  // double covariance_vel_y_vel_y;      // vel y
  double covariance_vel_y_vel_z;
  double covariance_vel_z_vel_z;      // vel z
} state_message_t;

typedef struct __attribute((packed)){
  uint64_t time_of_validity;
  double offset_x;
  double offset_y;
  double offset_z;
  double frame_rot_x;
  double frame_rot_y;
  double frame_rot_z;
  double attitude_scalar;
} offset_message_t;

typedef struct __attribute((packed)){
  uint32_t bit_request_type;
} do_bit_message_t;

#define MESSAGE_REPORT_PATH_SIZE 255          // should this be 255 or 256?
#define MESSAGE_REPORT_FILE_ID_SIZE 64
typedef struct __attribute((packed)){
  uint32_t bit_request_type;
  uint64_t bit_response;
  char report_path[MESSAGE_REPORT_PATH_SIZE];
  char report_file_id[MESSAGE_REPORT_FILE_ID_SIZE];
  uint64_t time_complete;
} bit_complete_status_message_t;

typedef struct __attribute((packed)){
  uint8_t battery_charge;
  uint8_t ldl_status;                         // no clue what this is
  uint64_t last_state_update_time;
  uint16_t enclosure_state;
  uint64_t payload_state;
  uint64_t error_code;
} telemerty_update_message_t;

typedef struct __attribute((packed)){
  uint64_t time_remaining;
  uint16_t shutdown_type;
} shutdown_message_t;

#define MESSAGE_PLATFORM_PATH_SIZE 256
#define MESSAGE_PAYLOAD_PATH_SIZE 256
typedef struct __attribute((packed)){
  uint16_t direction;
  uint16_t file_type;
  char platform_path[MESSAGE_PLATFORM_PATH_SIZE];
  char payload_path[MESSAGE_PAYLOAD_PATH_SIZE];
} start_file_transfer_message_t;

typedef struct __attribute((packed)){
  uint16_t sftp_status;
  uint16_t file_type;
  char platform_path[MESSAGE_PLATFORM_PATH_SIZE];
} file_transfer_complete_status_message_t;

typedef struct __attribute((packed)){
  uint16_t message_id;
} return_to_idle_message_t;

typedef struct __attribute((packed)){
  uint16_t message_id;
} resend_last_response_message_t;

typedef struct __attribute((packed)){
  uint16_t message_id;
} ack_message_t;

typedef struct __attribute((packed)){
  uint16_t nacked_message_id;
  uint8_t status;
  uint8_t error_code;
  uint16_t field_out_of_range;
} nack_message_t;

// Commented out since each message definition is two widely varied.
// typedef struct __attribute__((packed)){
//     message_header_t primary_header;
//     uint8_t data[MAX_DATA_LENGTH];
// } message_t;
    
#endif