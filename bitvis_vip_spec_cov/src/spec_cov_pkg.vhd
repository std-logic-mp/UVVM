--================================================================================================================================
-- Copyright 2020 Bitvis
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and in the provided LICENSE.TXT.
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and limitations under the License.
--================================================================================================================================
-- Note : Any functionality not explicitly described in the documentation is subject to change at any time
----------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
-- Description   : See library quick reference (under 'doc') and README-file(s)
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

use std.textio.all;

use work.csv_file_reader_pkg.all;
use work.local_adaptations_pkg.all;


package spec_cov_pkg is  

  alias config is shared_spec_cov_config;

  file RESULT_FILE : text;


  procedure initialize_req_cov(
    constant testcase         : string;
    constant req_list_file    : string;
    constant partial_cov_file : string
  );
  -- Overloading procedure
  procedure initialize_req_cov(
    constant testcase         : string;
    constant partial_cov_file : string
  );


  procedure tick_off_req_cov(
    constant requirement : string;
    constant testcase    : string;
    constant test_status : t_test_status  := NA;
    constant msg         : string         := "";
    constant scope       : string         := C_SCOPE
  );
  -- Overloading procedure
  procedure tick_off_req_cov(
    constant requirement : string;
    constant test_status : t_test_status  := NA;
    constant msg         : string         := "";
    constant scope       : string         := C_SCOPE
  );
  

  procedure finalize_req_cov(
    constant VOID : t_void
  );
  
  

  --=================================================================================================  
  -- Functions and procedures declared below this line are intended as private internal functions
  --=================================================================================================  

  type t_line_vector is array(0 to config.max_testcases_per_req-1) of line;
  type t_requirement_entry is record
    valid         : boolean;
    requirement   : line;
    description   : line;
    num_tcs       : natural;
    tc_list       : t_line_vector;
  end record;
  type t_requirement_entry_array is array (natural range <>) of t_requirement_entry;

  -- Shared variables used internally in this context
  shared variable shared_csv_file               : csv_file_reader_type;
  shared variable shared_requirement_array      : t_requirement_entry_array(0 to config.max_testcases_per_req);
  shared variable shared_requirements_in_array  : natural := 0;

  constant C_FAIL_STRING                : string := "FAIL";
  constant C_PASS_STRING                : string := "PASS";

  procedure priv_log_entry(
    constant index : natural
  );

  procedure priv_read_and_parse_csv_file(
    constant req_list_file  : string
  );

  procedure priv_initialize_result_file(
    constant file_name : string
  );

  impure function priv_get_description(
    requirement : string
  ) return string;

  impure function priv_requirement_exists(
    requirement : string
  ) return boolean;

  function priv_test_status_to_string(
    constant test_status : t_test_status
  ) return string;

  impure function priv_get_summary_string 
    return string;

  procedure priv_set_default_testcase_name(
    constant testcase : string
  );
  
  impure function priv_get_default_testcase_name 
  return string;

  impure function priv_find_string_length(
    constant search_string : string
  ) return natural;



end package spec_cov_pkg;


--=================================================================================================
--=================================================================================================
--=================================================================================================

package body spec_cov_pkg is

  -- private variables for pkg internal use only
  shared variable priv_testcase_name            : string(1 to C_CSV_FILE_MAX_LINE_LENGTH) := (others => NUL);
  shared variable priv_testcase_passed          : boolean;
  shared variable priv_requirement_file_exists  : boolean;
  

  --
  -- Initialize testcase requirement coverage
  --
  procedure initialize_req_cov(
    constant testcase         : string;
    constant req_list_file    : string;
    constant partial_cov_file : string
  ) is
  begin
    priv_set_default_testcase_name(testcase);
    -- update pkg local variables
    priv_testcase_passed          := true;
    priv_requirement_file_exists  := true;

    priv_read_and_parse_csv_file(req_list_file);    
    priv_initialize_result_file(partial_cov_file);
  end procedure initialize_req_cov;
  -- Overloading procedure
  procedure initialize_req_cov(
    constant testcase         : string;
    constant partial_cov_file : string
  ) is
  begin
    log(ID_SPEC_COV, "Requirement Coverage initialized with no requirement file.", C_SCOPE);
    priv_set_default_testcase_name(testcase);
    -- update pkg local variables
    priv_testcase_passed          := true;
    priv_requirement_file_exists  := false;

    priv_initialize_result_file(partial_cov_file);
    end procedure initialize_req_cov;
  

  --
  -- Log the requirement and testcase
  --
  procedure tick_off_req_cov(
    constant requirement : string;
    constant testcase    : string;
    constant test_status : t_test_status  := NA;
    constant msg         : string         := "";
    constant scope       : string         := C_SCOPE
  ) is
    variable v_requirement_to_file_line : line;
    variable v_requirement_status       : t_test_status;
  begin
    if shared_requirements_in_array = 0 and priv_requirement_file_exists = true then
      alert(TB_ERROR, "Requirements have not been parsed. Please use initialize_req_cov() with a requirement file before calling tick_off_req_cov().", scope);
      return;
    end if;

    -- Check if requirement exists
    if (priv_requirement_exists(requirement) = false) and (priv_requirement_file_exists = true) then
      alert(config.missing_req_label_severity, "Requirement not found in requirement list: " & to_string(requirement), C_SCOPE);
    end if;

    ---- Check if there were any errors globally or testcase was explicit set to FAIL
    if (shared_uvvm_status.found_unexpected_simulation_errors_or_worse = 1) or (test_status = FAIL) then
      v_requirement_status := FAIL;
      -- Set failing testcase for finishing summary line
      priv_testcase_passed := false;
    else
      v_requirement_status := PASS;
    end if;

    -- Log result to transcript
    log(ID_SPEC_COV, "Logging requirement " & requirement & " [" & priv_test_status_to_string(v_requirement_status) & "]. '" & 
                      priv_get_description(requirement) & "'. " & msg, scope);

    -- Log to file
    write(v_requirement_to_file_line, requirement & C_CSV_DELIMITER & testcase & C_CSV_DELIMITER & priv_test_status_to_string(v_requirement_status));
    writeline(RESULT_FILE, v_requirement_to_file_line);
  end procedure tick_off_req_cov;

  -- Overloading procedure
  procedure tick_off_req_cov(
    constant requirement : string;
    constant test_status : t_test_status  := NA;
    constant msg         : string         := "";
    constant scope       : string         := C_SCOPE
  ) is 
  begin
    tick_off_req_cov(requirement, priv_get_default_testcase_name , test_status, msg, scope);
  end procedure tick_off_req_cov;
  
  
  --
  -- Deallocate memory usage and write summary line to partial_cov file
  --
  procedure finalize_req_cov(
    constant VOID : t_void
  ) is
    variable v_checksum_string : line;
  begin
    -- Free used memory
    log(ID_SPEC_COV, "Freeing stored requirements from memory", C_SCOPE);

    for i in 0 to shared_requirements_in_array-1 loop
      deallocate(shared_requirement_array(i).requirement);
      deallocate(shared_requirement_array(i).description);
      for tc in 0 to shared_requirement_array(i).num_tcs-1 loop
        deallocate(shared_requirement_array(i).tc_list(tc));
      end loop;
      shared_requirement_array(i).num_tcs := 0;
      shared_requirement_array(i).valid   := false;
    end loop;
    shared_requirements_in_array := 0;
        
    -- Add closing line
    log(ID_SPEC_COV, "Marking requirement coverage result.", C_SCOPE);
    write(v_checksum_string, priv_get_summary_string);

    writeline(RESULT_FILE, v_checksum_string);

    file_close(RESULT_FILE);
    log(ID_SPEC_COV, "Requirement coverage finalized.", C_SCOPE);
  end procedure finalize_req_cov;
  


  
  --=================================================================================================  
  -- Functions and procedures declared below this line are intended as private internal functions
  --=================================================================================================  


  --
  -- Initialize the partial_cov result file
  --
  procedure priv_initialize_result_file(
    constant file_name : string
  ) is
    variable v_file_open_status      : FILE_OPEN_STATUS;
    variable v_settings_to_file_line : line;
  begin
    file_open(v_file_open_status, RESULT_FILE, file_name, write_mode);
    check_file_open_status(v_file_open_status, file_name);

    -- Write info and settings to CSV file for Python post-processing script
    log(ID_SPEC_COV, "Adding test and configuration information to coverage file. ", C_SCOPE);
    write(v_settings_to_file_line, "NOTE: This coverage file is only valid when the last line is 'SUMMARY, " & priv_get_default_testcase_name & ", PASS'" & LF);
    write(v_settings_to_file_line, "TESTCASE_NAME: " & priv_get_default_testcase_name & LF);
    write(v_settings_to_file_line, "DELIMITER: " & config.csv_delimiter & LF);
    writeline(RESULT_FILE, v_settings_to_file_line);
  end procedure priv_initialize_result_file;


  --
  -- Read requirement CSV file
  --
  procedure priv_read_and_parse_csv_file(
      constant req_list_file  : string
  ) is 
    variable v_tc_valid : boolean;
    variable v_file_ok  : boolean;
  begin
    log(ID_SPEC_COV, "Reading and parsing requirement file, " & req_list_file, C_SCOPE);

    if shared_requirements_in_array > 0 then
      alert(TB_ERROR, "Requirements have already been read from file, please call finalize_req_cov before starting a new requirement coverage process.", C_SCOPE);
      return;
    end if;

    -- Open file and check status, return if failing
    v_file_ok := shared_csv_file.initialize(req_list_file, C_CSV_DELIMITER);
    if v_file_ok = false then
      return;
    end if;

    -- File ok, read file
    while not shared_csv_file.end_of_file loop
      shared_csv_file.readline;

      -- Read requirement
      shared_requirement_array(shared_requirements_in_array).requirement := new string'(shared_csv_file.read_string);
      -- Read description
      shared_requirement_array(shared_requirements_in_array).description := new string'(shared_csv_file.read_string);
      -- Read testcases
      v_tc_valid := true;
      shared_requirement_array(shared_requirements_in_array).num_tcs := 0;
      while v_tc_valid loop
        shared_requirement_array(shared_requirements_in_array).tc_list(shared_requirement_array(shared_requirements_in_array).num_tcs) := new string'(shared_csv_file.read_string);  
        if (shared_requirement_array(shared_requirements_in_array).tc_list(shared_requirement_array(shared_requirements_in_array).num_tcs).all(1) /= NUL) then
          shared_requirement_array(shared_requirements_in_array).num_tcs := shared_requirement_array(shared_requirements_in_array).num_tcs + 1;
        else
          v_tc_valid := false;
        end if;
      end loop;
      -- Validate entry
      shared_requirement_array(shared_requirements_in_array).valid := true;

      priv_log_entry(shared_requirements_in_array);
      shared_requirements_in_array := shared_requirements_in_array + 1;
    end loop;
        
    log(ID_SPEC_COV, "Closing requirement file", C_SCOPE);
    shared_csv_file.dispose;
  end procedure priv_read_and_parse_csv_file;


  --
  -- Log CSV readout to terminal
  --
  procedure priv_log_entry(
      constant index : natural
    ) is
  begin
    if shared_requirement_array(index).valid then
      -- log requirement and description to terminal
      log(ID_SPEC_COV, "Requirement: " & shared_requirement_array(index).requirement.all, C_SCOPE);
      log(ID_SPEC_COV, "Description: " & shared_requirement_array(index).description.all, C_SCOPE);
      -- log testcases to terminal
      for i in 0 to shared_requirement_array(index).num_tcs-1 loop
        log(ID_SPEC_COV, "  TC: " & shared_requirement_array(index).tc_list(i).all, C_SCOPE);
      end loop;
    else
      log(ID_SPEC_COV, "Requirement entry was not valid", C_SCOPE);
    end if;
  end procedure priv_log_entry;


  --
  -- Check if requirement exists, return boolean
  -- 
  impure function priv_requirement_exists(
    requirement : string
  ) return boolean is
  begin
    for i in 0 to shared_requirements_in_array-1 loop
      if to_upper(shared_requirement_array(i).requirement.all(1 to requirement'length)) = to_upper(requirement(1 to requirement'length)) then
        return true;
      end if;
    end loop;
    return false;
  end function priv_requirement_exists;


  --
  -- Get description of requirement
  --
  impure function priv_get_description(
      requirement : string
  ) return string is
  begin
    for i in 0 to shared_requirements_in_array-1 loop
      if shared_requirement_array(i).requirement.all(1 to requirement'length) = requirement(1 to requirement'length) then
        -- Found requirement
        return shared_requirement_array(i).description.all;
      end if;
    end loop;

    if priv_requirement_file_exists = false then
      return "";
    else
      return "DESCRIPTION NOT FOUND";
    end if;
  end function priv_get_description;


  --
  -- Get the t_test_status parameter as string
  --
  function priv_test_status_to_string(
    constant test_status : t_test_status
  ) return string is
  begin
    if test_status = PASS then
      return C_PASS_STRING;
    else -- test_status = FAIL
      return C_FAIL_STRING;
    end if;
  end function priv_test_status_to_string;


  --
  -- Get a string for finalize summary in the partial_cov CSV file.
  --
  impure function priv_get_summary_string 
    return string is
  begin
    -- Create a CSV coverage file summary string
    if (priv_testcase_passed = true) and (shared_uvvm_status.found_unexpected_simulation_errors_or_worse = 0) then
      return "SUMMARY, " & priv_get_default_testcase_name & ", " & C_PASS_STRING;
    else
      return "SUMMARY, " & priv_get_default_testcase_name & ", " & C_FAIL_STRING;
    end if;
  end function priv_get_summary_string;


  --
  -- Set the default testcase name.
  --
  procedure priv_set_default_testcase_name(
    constant testcase : string
  ) is
  begin
    priv_testcase_name(1 to testcase'length)  := testcase;
  end procedure priv_set_default_testcase_name;


  --
  -- Return the default testcase name set when initialize_req_cov() was called.
  --
  impure function priv_get_default_testcase_name 
    return string is
    variable v_testcase_length : natural := priv_find_string_length(priv_testcase_name);
  begin 
    return priv_testcase_name(1 to v_testcase_length);
  end function priv_get_default_testcase_name;


  --
  -- Find the length of a string which will contain NUL characters.
  --
  impure function priv_find_string_length(
    constant search_string : string
  ) return natural is
    variable v_return : natural := 0;
  begin
    -- loop string until NUL is found and return idx-1
    for idx in 1 to search_string'length loop
      if search_string(idx) = NUL then
        return idx - 1;
      end if;
    end loop;

    -- NUL was not found, return full length
    return search_string'length;
  end function priv_find_string_length;

end package body spec_cov_pkg;