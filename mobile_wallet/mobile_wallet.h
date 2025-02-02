#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * Take a pointer to a NUL-terminated UTF8-string and return whether this is
 * a correct format for a concordium address.
 * A non-zero return value signals success.
 * #Safety
 * The input must be NUL-terminated.
 */
uint8_t check_account_address(const char *input_ptr);

/**
 * Take a pointer to two NUL-terminated UTF8-strings and return a
 * NUL-terminated UTF8-encoded string. The returned string must be freed by the
 * caller by calling the function 'free_response_string'. In case of failure
 * the function returns an error message as the response, and sets the
 * 'success' flag to 0.
 *
 * See rust-bins/wallet-notes/README.md for the description of input and output
 * formats.
 *
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
char *combine_encrypted_amounts(const char *input_ptr_1, const char *input_ptr_2, uint8_t *success);

/**
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
char *generate_accounts(const char *input_ptr, uint8_t *success);

/**
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
char *create_credential(const char *input_ptr, uint8_t *success);

/**
 * Take a pointer to a NUL-terminated UTF8-string and return a NUL-terminated
 * UTF8-encoded string. The returned string must be freed by the caller by
 * calling the function 'free_response_string'. In case of failure the function
 * returns an error message as the response, and sets the 'success' flag to 0.
 *
 * See rust-bins/wallet-notes/README.md for the description of input and output
 * formats.
 *
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
char *create_encrypted_transfer(const char *input_ptr, uint8_t *success);

/**
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
char *create_id_request_and_private_data(const char *input_ptr, uint8_t *success);

/**
 * Take a pointer to a NUL-terminated UTF8-string and return a NUL-terminated
 * UTF8-encoded string. The returned string must be freed by the caller by
 * calling the function 'free_response_string'. In case of failure the function
 * returns an error message as the response, and sets the 'success' flag to 0.
 *
 * See rust-bins/wallet-notes/README.md for the description of input and output
 * formats.
 *
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
char *create_pub_to_sec_transfer(const char *input_ptr, uint8_t *success);

/**
 * Take a pointer to a NUL-terminated UTF8-string and return a NUL-terminated
 * UTF8-encoded string. The returned string must be freed by the caller by
 * calling the function 'free_response_string'. In case of failure the function
 * returns an error message as the response, and sets the 'success' flag to 0.
 *
 * See rust-bins/wallet-notes/README.md for the description of input and output
 * formats.
 *
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
char *create_sec_to_pub_transfer(const char *input_ptr, uint8_t *success);

/**
 * Take a pointer to a NUL-terminated UTF8-string and return a NUL-terminated
 * UTF8-encoded string. The returned string must be freed by the caller by
 * calling the function 'free_response_string'. In case of failure the function
 * returns an error message as the response, and sets the 'success' flag to 0.
 *
 * See rust-bins/wallet-notes/README.md for the description of input and output
 * formats.
 *
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
char *create_transfer(const char *input_ptr, uint8_t *success);

/**
 * Take a pointer to a NUL-terminated UTF8-string and return a NUL-terminated
 * UTF8-encoded string. The returned string must be freed by the caller by
 * calling the function 'free_response_string'. In case of failure the function
 * returns an error message as the response, and sets the 'success' flag to 0.
 *
 * See rust-bins/wallet-notes/README.md for the description of input and output
 * formats.
 *
 * # Safety
 * The input pointer must point to a null-terminated buffer, otherwise this
 * function will fail in unspecified ways.
 */
uint64_t decrypt_encrypted_amount(const char *input_ptr, uint8_t *success);

/**
 * # Safety
 * This function is unsafe in the sense that if the argument pointer was not
 * Constructed via CString::into_raw its behaviour is undefined.
 */
void free_response_string(char *ptr);
