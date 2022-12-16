///  static const String PostgreSQL Error Codes
///  static const String https://www.postgresql.org/docs/current/errcodes-appendix.html
class PostgreSQLErrorCodes {
  String asString(String code) {
    switch (code) {
      case successful_completion:
        return 'successful completion';
      case warning:
        return 'warning';
      case dynamic_result_sets_returned:
        return 'dynamic result sets returned';
      case implicit_zero_bit_padding:
        return 'implicit zero bit padding';
      case null_value_eliminated_in_set_function:
        return 'null value eliminated in set function';
      case privilege_not_granted:
        return 'privilege not granted';
    }
    return 'unknow';
  }

//   String Class 00 — Successful Completion
  static const String successful_completion = '00000';
//   String Class 01 — Warning
  static const String warning = '01000';
  static const String dynamic_result_sets_returned = '0100C';
  static const String implicit_zero_bit_padding = '01008';
  static const String null_value_eliminated_in_set_function = '01003';
  static const String privilege_not_granted = '01007';
  static const String privilege_not_revoked = '01006';
  static const String warning_string_data_right_truncation = '01004';
  static const String deprecated_feature = '01P01';
//   Class 02 — No Data (this is also a warning //  static const String Class per the SQL standard)
  static const String no_data = '02000';
  static const String no_additional_dynamic_result_sets_returned = '02001';
//   Class 03 — SQL Statement Not Yet Complete
  static const String sql_statement_not_yet_complete = '03000';
//   Class 08 — Connection Exception
  static const String connection_exception = '08000';
  static const String connection_does_not_exist = '08003';
  static const String connection_failure = '08006';
  static const String sqlclient_unable_to_establish_sqlconnection = '08001';
  static const String sqlserver_rejected_establishment_of_sqlconnection =
      '08004';
  static const String transaction_resolution_unknown = '08007';
  static const String protocol_violation = '08P01';

  //   Class 09 — Triggered Action Exception
  static const String triggered_action_exception = '09000';

  // Class 0A — Feature Not Supported
  static const String feature_not_supported = '0A000';

  // Class 0B — Invalid Transaction Initiation
  static const String invalid_transaction_initiation = '0B000';

  // Class 0F — Locator Exception
  static const String locator_exception = '0F000';
  static const String invalid_locator_specification = '0F001';

  // Class 0L — Invalid Grantor
  static const String invalid_grantor = '0L000';
  static const String invalid_grant_operation = '0LP01';

  // Class 0P — Invalid Role Specification
  static const String invalid_role_specification = '0P000';

  //  Class 0Z — Diagnostics Exception
  static const String diagnostics_exception = '0Z000';
  static const String stacked_diagnostics_accessed_without_active_handler =
      '0Z002';

  //   Class 20 — Case Not Found
  static const String case_not_found = '20000';

  //   Class 21 — Cardinality Violation
  static const String cardinality_violation = '21000';

  //   Class 22 — Data Exception
  static const String data_exception = '22000';
  static const String array_subscript_error = '2202E';
  static const String character_not_in_repertoire = '22021';
  static const String datetime_field_overflow = '22008';
  static const String division_by_zero = '22012';
  static const String error_in_assignment = '22005';
  static const String escape_character_conflict = '2200B';
  static const String indicator_overflow = '22022';
  static const String interval_field_overflow = '22015';
  static const String invalid_argument_for_logarithm = '2201E';
  static const String invalid_argument_for_ntile_function = '22014';
  static const String invalid_argument_for_nth_value_function = '22016';
  static const String invalid_argument_for_power_function = '2201F';
  static const String invalid_argument_for_width_bucket_function = '2201G';
  static const String invalid_character_value_for_cast = '22018';
  static const String invalid_datetime_format = '22007';
  static const String invalid_escape_character = '22019';
  static const String invalid_escape_octet = '2200D';
  static const String invalid_escape_sequence = '22025';
  static const String nonstandard_use_of_escape_character = '22P06';
  static const String invalid_indicator_parameter_value = '22010';
  static const String invalid_parameter_value = '22023';
  static const String invalid_preceding_or_following_size = '22013';
  static const String invalid_regular_expression = '2201B';
  static const String invalid_row_count_in_limit_clause = '2201W';
  static const String invalid_row_count_in_result_offset_clause = '2201X';
  static const String invalid_tablesample_argument = '2202H';
  static const String invalid_tablesample_repeat = '2202G';
  static const String invalid_time_zone_displacement_value = '22009';
  static const String invalid_use_of_escape_character = '2200C';
  static const String most_specific_type_mismatch = '2200G';
  static const String null_value_not_allowed = '22004';
  static const String null_value_no_indicator_parameter = '22002';
  static const String numeric_value_out_of_range = '22003';
  static const String sequence_generator_limit_exceeded = '2200H';
  static const String string_data_length_mismatch = '22026';
  static const String data_exception_string_data_right_truncation = '22001';
  static const String substring_error = '22011';
  static const String trim_error = '22027';
  static const String unterminated_c_string = '22024';
  static const String zero_length_character_string = '2200F';
  static const String floating_point_exception = '22P01';
  static const String invalid_text_representation = '22P02';
  static const String invalid_binary_representation = '22P03';
  static const String bad_copy_file_format = '22P04';
  static const String untranslatable_character = '22P05';
  static const String not_an_xml_document = '2200L';
  static const String invalid_xml_document = '2200M';
  static const String invalid_xml_content = '2200N';
  static const String invalid_xml_comment = '2200S';
  static const String invalid_xml_processing_instruction = '2200T';
  static const String duplicate_json_object_key_value = '22030';
  static const String invalid_argument_for_sql_json_datetime_function = '22031';
  static const String invalid_json_text = '22032';
  static const String invalid_sql_json_subscript = '22033';
  static const String more_than_one_sql_json_item = '22034';
  static const String no_sql_json_item = '22035';
  static const String non_numeric_sql_json_item = '22036';
  static const String non_unique_keys_in_a_json_object = '22037';
  static const String singleton_sql_json_item_required = '22038';
  static const String sql_json_array_not_found = '22039';
  static const String sql_json_member_not_found = '2203A';
  static const String sql_json_number_not_found = '2203B';
  static const String sql_json_object_not_found = '2203C';
  static const String too_many_json_array_elements = '2203D';
  static const String too_many_json_object_members = '2203E';
  static const String sql_json_scalar_required = '2203F';
  static const String sql_json_item_cannot_be_cast_to_target_type = '2203G';
  // Class 23 — Integrity Constraint Violation
  static const String integrity_constraint_violation = '23000';
  static const String restrict_violation = '23001';
  static const String not_null_violation = '23502';
  static const String foreign_key_violation = '23503';
  static const String unique_violation = '23505';
  static const String check_violation = '23514';
  static const String exclusion_violation = '23P01';
  //Class 24 — Invalid Cursor State
  static const String invalid_cursor_state = '24000';
  // Class 25 — Invalid Transaction State
  static const String invalid_transaction_state = '25000';
  static const String active_sql_transaction = '25001';
  static const String branch_transaction_already_active = '25002';
  static const String held_cursor_requires_same_isolation_level = '25008';
  static const String inappropriate_access_mode_for_branch_transaction =
      '25003';
  static const String inappropriate_isolation_level_for_branch_transaction =
      '25004';
  static const String no_active_sql_transaction_for_branch_transaction =
      '25005';
  static const String read_only_sql_transaction = '25006';
  static const String schema_and_data_statement_mixing_not_supported = '25007';
  static const String no_active_sql_transaction = '25P01';
  static const String in_failed_sql_transaction = '25P02';
  static const String idle_in_transaction_session_timeout = '25P03';
  //Class 26 — Invalid SQL Statement Name
  static const String invalid_sql_statement_name = '26000';
  //Class 27 — Triggered Data Change Violation
  static const String triggered_data_change_violation = '27000';
  // Class 28 — Invalid Authorization Specification
  static const String invalid_authorization_specification = '28000';
  static const String invalid_password = '28P01';
  //Class 2B — Dependent Privilege Descriptors Still Exist
  static const String dependent_privilege_descriptors_still_exist = '2B000';
  static const String dependent_objects_still_exist = '2BP01';
  // Class 2D — Invalid Transaction Termination
  static const String invalid_transaction_termination = '2D000';
  // Class 2F — SQL Routine Exception
  static const String sql_routine_exception = '2F000';
  static const String function_executed_no_return_statement = '2F005';
  static const String modifying_sql_data_not_permitted = '2F002';
  static const String prohibited_sql_statement_attempted = '2F003';
  static const String reading_sql_data_not_permitted = '2F004';
  //  Class 34 — Invalid Cursor Name
  static const String invalid_cursor_name = '34000';
  //  Class 38 — External Routine Exception
  static const String external_routine_exception = '38000';
  static const String containing_sql_not_permitted = '38001';
  static const String Routine_Exception_modifying_sql_data_not_permitted =
      '38002';
  static const String Routine_Exception_prohibited_sql_statement_attempted =
      '38003';
  static const String Routine_Exception_reading_sql_data_not_permitted =
      '38004';
  // Class 39 — External Routine Invocation Exception
  static const String external_routine_invocation_exception = '39000';
  static const String invalid_sqlstate_returned = '39001';
  static const String Invocation_Exception_null_value_not_allowed = '39004';
  static const String trigger_protocol_violated = '39P01';
  static const String srf_protocol_violated = '39P02';
  static const String event_trigger_protocol_violated = '39P03';
  // Class 3B — Savepoint Exception
  static const String savepoint_exception = '3B000';
  static const String invalid_savepoint_specification = '3B001';
  //Class 3D — Invalid Catalog Name
  static const String invalid_catalog_name = '3D000';
  //Class 3F — Invalid Schema Name
  static const String invalid_schema_name = '3F000';
  //Class 40 — Transaction Rollback
  static const String transaction_rollback = '40000';
  static const String transaction_integrity_constraint_violation = '40002';
  static const String serialization_failure = '40001';
  static const String statement_completion_unknown = '40003';
  static const String deadlock_detected = '40P01';
  //Class 42 — Syntax Error or Access Rule Violation
  static const String syntax_error_or_access_rule_violation = '42000';
  static const String syntax_error = '42601';
  static const String insufficient_privilege = '42501';
  static const String cannot_coerce = '42846';
  static const String grouping_error = '42803';
  static const String windowing_error = '42P20';
  static const String invalid_recursion = '42P19';
  static const String invalid_foreign_key = '42830';
  static const String invalid_name = '42602';
  static const String name_too_long = '42622';
  static const String reserved_name = '42939';
  static const String datatype_mismatch = '42804';
  static const String indeterminate_datatype = '42P18';
  static const String collation_mismatch = '42P21';
  static const String indeterminate_collation = '42P22';
  static const String wrong_object_type = '42809';
  static const String generated_always = '428C9';
  static const String undefined_column = '42703';
  static const String undefined_function = '42883';
  static const String undefined_table = '42P01';
  static const String undefined_parameter = '42P02';
  static const String undefined_object = '42704';
  static const String duplicate_column = '42701';
  static const String duplicate_cursor = '42P03';
  static const String duplicate_database = '42P04';
  static const String duplicate_function = '42723';
  static const String duplicate_prepared_statement = '42P05';
  static const String duplicate_schema = '42P06';
  static const String duplicate_table = '42P07';
  static const String duplicate_alias = '42712';
  static const String duplicate_object = '42710';
  static const String ambiguous_column = '42702';
  static const String ambiguous_function = '42725';
  static const String ambiguous_parameter = '42P08';
  static const String ambiguous_alias = '42P09';
  static const String invalid_column_reference = '42P10';
  static const String invalid_column_definition = '42611';
  static const String invalid_cursor_definition = '42P11';
  static const String invalid_database_definition = '42P12';
  static const String invalid_function_definition = '42P13';
  static const String invalid_prepared_statement_definition = '42P14';
  static const String invalid_schema_definition = '42P15';
  static const String invalid_table_definition = '42P16';
  static const String invalid_object_definition = '42P17';

  ///  Class 44 — WITH CHECK OPTION Violation
  static const String with_check_option_violation = '44000';

  /// Class 53 — Insufficient Resources
  static const String insufficient_resources = '53000';
  static const String disk_full = '53100';
  static const String out_of_memory = '53200';
  static const String too_many_connections = '53300';
  static const String configuration_limit_exceeded = '53400';
//   Class 54 — Program Limit Exceeded
  static const String program_limit_exceeded = '54000';
  static const String statement_too_complex = '54001';
  static const String too_many_columns = '54011';
  static const String too_many_arguments = '54023';
//   Class 55 — Object Not In Prerequisite State
  static const String object_not_in_prerequisite_state = '55000';
  static const String object_in_use = '55006';
  static const String cant_change_runtime_param = '55P02';
  static const String lock_not_available = '55P03';
  static const String unsafe_new_enum_value_usage = '55P04';
//   Class 57 — Operator Intervention
  static const String operator_intervention = '57000';
  static const String query_canceled = '57014';
  static const String admin_shutdown = '57P01';
  static const String crash_shutdown = '57P02';
  static const String cannot_connect_now = '57P03';
  static const String database_dropped = '57P04';
  static const String idle_session_timeout = '57P05';
//   Class 58 — System Error (errors external to PostgreSQL itself)
  static const Stringsystem_error = '58000';
  static const String io_error = '58030';
  static const String undefined_file = '58P01';
  static const String duplicate_file = '58P02';
//   Class 72 — Snapshot Failure
  static const String snapshot_too_old = '72000';
//   Class F0 — Configuration File Error
  static const Stringconfig_file_error = 'F0000';
  static const String lock_file_exists = 'F0001';
//   Class HV — Foreign Data Wrapper Error (SQL/MED)
  static const String fdw_error = 'HV000';
  static const String fdw_column_name_not_found = 'HV005';
  static const String fdw_dynamic_parameter_value_needed = 'HV002';
  static const String fdw_function_sequence_error = 'HV010';
  static const String fdw_inconsistent_descriptor_information = 'HV021';
  static const String fdw_invalid_attribute_value = 'HV024';
  static const String fdw_invalid_column_name = 'HV007';
  static const String fdw_invalid_column_number = 'HV008';
  static const String fdw_invalid_data_type = 'HV004';
  static const String fdw_invalid_data_type_descriptors = 'HV006';
  static const String fdw_invalid_descriptor_field_identifier = 'HV091';
  static const String fdw_invalid_handle = 'HV00B';
  static const String fdw_invalid_option_index = 'HV00C';
  static const String fdw_invalid_option_name = 'HV00D';
  static const String fdw_invalid_string_length_or_buffer_length = 'HV090';
  static const String fdw_invalid_string_format = 'HV00A';
  static const String fdw_invalid_use_of_null_pointer = 'HV009';
  static const String fdw_too_many_handles = 'HV014';
  static const String fdw_out_of_memory = 'HV001';
  static const String fdw_no_schemas = 'HV00P';
  static const String fdw_option_name_not_found = 'HV00J';
  static const String fdw_reply_handle = 'HV00K';
  static const String fdw_schema_not_found = 'HV00Q';
  static const String fdw_table_not_found = 'HV00R';
  static const String fdw_unable_to_create_execution = 'HV00L';
  static const String fdw_unable_to_create_reply = 'HV00M';
  static const String fdw_unable_to_establish_connection = 'HV00N';
//   Class P0 — PL/pgSQL Error
  static const String plpgsql_error = 'P0000';
  static const String raise_exception = 'P0001';
  static const String no_data_found = 'P0002';
  static const String too_many_rows = 'P0003';
  static const String assert_failure = 'P0004';
//   Class XX — Internal Error
  static const String internal_error = 'XX000';
  static const String data_corrupted = 'XX001';
  static const String index_corrupted = 'XX002';
}
