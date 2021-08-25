#!/home/red/anaconda2/bin/python
import os
try:
    import pyodbc
except ImportError:
    pass
try:
    import psycopg2
except ImportError:
    pass
import boto3
import sys
import types
import getopt
import re
import datetime
import time
import getpass
import collections
import smtplib
from email.mime.text import MIMEText

try:
    from joblib import Parallel, delayed  
except ImportError:
    pass

def get_config_file_name():
    cwd = os.path.dirname(os.path.realpath(__file__))
    return os.path.join(cwd, "sqlrunnor.ini")
       
def get_run_tracking_table(use_list):
    return use_list.get('RUN_TRACKING_TABLE', "")
    
def get_run_type(use_list):
    return use_list.get('RUN_TYPE', "")
    
def get_backup_tag(use_list):
    return use_list.get('BACKUP_TAG', "")

def get_vertica_or_redshift(use_list):
    return use_list.get('VERTICA_OR_REDSHIFT', "VERTICA")

def add_spaces_delim(delim):
    if delim == ",":
        delim_str = ", "
    elif delim == "|":
        delim_str = " | "
    else:
        delim_str = delim
    return delim_str
    
def get_csv_hdr_delim(use_list):
    delim = use_list.get('CSV_HEADER_DELIMITER', '\035')
    return add_spaces_delim(delim)
    
def get_csv_delim(use_list):
    delim = use_list.get('CSV_DELIMITER', '\035')
    return add_spaces_delim(delim)
 
def get_out_fetch_size(use_list):
    return int(use_list.get("OUT_FETCH_SIZE", "1"))

def get_contents_of_file(file_name):
    file = open(file_name, "r")    
    file_contents = file.read()
    file.close()
    return file_contents

def get_config_if_missing(config_name, config_list):
    if (config_name in config_list):
        sys.stderr.write("SQLRUNNOR - %s = %s\n" % (config_name, config_list[config_name]))
    else:
        sys.stderr.write("Please enter the %s: " % config_name)
        config_list[config_name] =  raw_input("")
    return config_list
    
def get_configs():
    file_contents = get_contents_of_file(get_config_file_name())    
    config_list = {}
    config_list["CONNECTION_TYPE"] = "ODBC" # default value

    config_lines_only = ""
    for line in file_contents.splitlines():
            config_lines_only = config_lines_only + line.split("#")[0].strip() + "\n"   
   
    for line in config_lines_only.splitlines():
        if '=' in line:
            line_split = line.split('=', 1)    
            config_list[line_split[0].strip().upper()] = line_split[1].strip()

    get_config_if_missing("CONNECTION_TYPE", config_list)
    
    if config_list["CONNECTION_TYPE"] == "ODBC":
        get_config_if_missing("DSN", config_list)
        get_config_if_missing("UID", config_list)
    else: # when JDBC or default        
        get_config_if_missing("HOST", config_list)
        get_config_if_missing("DBNAME", config_list)
        get_config_if_missing("PORT", config_list)
        get_config_if_missing("USER", config_list)
           
    if not ("PWD" in config_list):
        config_list["PWD"] = getpass.getpass(prompt="Please enter the Password: ", stream=sys.stderr)
            
    return config_list

def parse_s3_location(s3_location):
    s3_parsed = {}
    #search_results = re.search("s3://(.[^/]*)/(.*/)(.*)", s3_location)
    search_results = re.search("(s3://)(.*)", s3_location)
    if search_results:
        groups = search_results.groups()
        s3_parsed['s3'] = True
        search_results = re.search("([^/]*)/(.*)", groups[1])
        if search_results:
            groups = search_results.groups()
            s3_parsed['bucket'] = groups[0]
            if groups[1] == '':
                s3_parsed['type'] = 'bucket'
            else:
                folder_or_file = groups[1]
                if folder_or_file.endswith('/'):             
                    s3_parsed['folder'] = folder_or_file
                    s3_parsed['type'] = "folder"
                else:
                    search_results = re.search("(.*)/(.*)", folder_or_file)
                    if search_results:
                        groups = search_results.groups()
                        s3_parsed['folder'] = groups[0]
                        s3_parsed['file'] = groups[1]
                        s3_parsed['type'] = "file"
                    else:
                        s3_parsed['file'] = folder_or_file
                        s3_parsed['type'] = "file"
#            if groups[2] == '':
#                s3_parsed['type'] = 'folder'
#            else:
#                s3_parsed['type'] = 'file'
#                s3_parsed['filename'] = groups[2]
    else:
        s3_parsed['s3'] = False
    return s3_parsed
    
def read_from_file(input_file):
    file_contents = ""
    s3_parsed = parse_s3_location(input_file)
    if (s3_parsed['s3']):
        s3 = boto3.resource('s3')
        bucket = s3.Bucket(s3_parsed['bucket'])   
        for obj in bucket.objects.filter(Prefix =s3_parsed['file']):
            file_contents = obj.get()['Body'].read()
    else:
        file = open(input_file, "r")    
        file_contents = file.read()
        file.close()  
    return file_contents

def write_to_file(output_file, output_to_write):
    file = open(output_file, "w")
    file.write(output_to_write)
    file.close() 
    return
    
def connect_db(config_list):
    if config_list["CONNECTION_TYPE"] == "ODBC":
        dsn = config_list["DSN"]
        uid = config_list["UID"]
        pwd = config_list["PWD"]
    
        conn_string = "DSN=" + dsn + ";UID=" + uid + ";PWD=" + pwd
        conn = pyodbc.connect(conn_string)
    else: # JDBC or default
        host = config_list["HOST"]
        dbname = config_list["DBNAME"]
        port = config_list["PORT"]
        user = config_list["USER"]
        pwd = config_list["PWD"]
    
        conn_string = "dbname = '" + dbname + "' port = '" + port + "' user = '" + user + "' password = '" + pwd + "' host = '" + host + "'"
        conn = psycopg2.connect(conn_string)    
    return conn

def send_email_msg(debug_only_option, config_list, email_msg):
    if debug_only_option:
        return
    if not ("SMTP_SERVER" in config_list and "EMAIL_FROM" in config_list and "EMAIL_TO" in config_list):
            return

    if not (config_list["SMTP_SERVER"] and config_list["EMAIL_FROM"] and config_list["EMAIL_TO"]):
        return

    server = smtplib.SMTP(config_list["SMTP_SERVER"])

    msg = MIMEText(email_msg, 'plain')
    email_from = config_list["EMAIL_FROM"]
    email_to = config_list["EMAIL_TO"]
    email_subject = config_list["EMAIL_SUBJECT"]

    msg['From'] = email_from
    msg['To'] = email_to
    msg['Subject'] = email_subject
          
    server.sendmail(email_from, config_list["EMAIL_TO"].split(";"), msg.as_string())
    server.quit()

def sql_ok(sql_cmd):
    return sql_cmd != ""
            
def split_manifest_lines(input_to_run):
    input_with_comments_removed = ""
    for line in input_to_run.splitlines():
        input_with_comments_removed = input_with_comments_removed + line.split("#")[0].strip() + "\n"   
 
    split_list = re.split(r'(USESQL|SETSQL|GENSQL|EXECSQL|OUTCSV)(?i)', input_with_comments_removed)
    
    #print split_list
    
    statements_list = []

    for i in range(0, len(split_list)):    
        if (split_list[i] == "USESQL" or split_list[i] == "SETSQL" or split_list[i] == "GENSQL" or split_list[i] == "EXECSQL" or split_list[i] == "OUTCSV"):
            statements_list.append((split_list[i].upper(), split_list[i+1].strip()))
        else:
            pass
    #print "*** Statements List ***"
    #print statements_list
    return statements_list
    
def replace_with_sets(input_line, set_list):
    return_line = input_line
    for set_orig, set_new in set_list.iteritems():
        handle_slash035 = re.compile('\035')
        return_line = handle_slash035.sub(r'\\035', return_line)
        case_insensitive = re.compile(re.escape(set_orig), re.IGNORECASE)
        return_line = case_insensitive.sub(set_new, return_line)
    return return_line 
                     
def get_table_name(input_line):
    return input_line.splitlines()[0].strip()

def get_input_sql_file_name(input_line):
    return input_line.splitlines()[0].strip() + ".sql"
    
def get_out_csv_file_name(output_folder, input_line):
    return os.path.join(output_folder, input_line.splitlines()[0].strip() + ".csv")

def get_dist_style(input_line):
    for line in input_line.splitlines():
        if "DISTSTYLE" in line.upper():
            return line
    return ""

def get_dist_key(input_line):
    for line in input_line.splitlines():
        if "DISTKEY" in line.upper():
            return line
    return ""

def get_sort_key(input_line):
    for line in input_line.splitlines():
        if "SORTKEY" in line.upper():
            return line
    return ""

def get_order_by(input_line):
    for line in input_line.splitlines():
        if "ORDER BY" in line.upper():
            return line
    return ""
    
def get_segmented_by(input_line):
    for line in input_line.splitlines():
        if "SEGMENTED BY" in line.upper():
            return line
        if "UNSEGMENTED" in line.upper():
            return line
    return ""

def get_run_loop(input_line):
    for line in input_line.splitlines():
        if "RUNLOOP" in line.upper():
            return line
    return ""

def get_tmp_handling(input_line):
    for line in input_line.splitlines():
        if "INSERT_FROM_TMP" in line.upper():
            return "insert_from_tmp"
    return "rename_tmp"

def get_merge_into_tmp_list(input_line):
    merge_list = []
    for line in input_line.splitlines():
        if "MERGE_INTO_TMP" in line.upper():
            merge_list.append(line.replace("MERGE_INTO_TMP ", ""))
    print merge_list
    return merge_list
    
def get_grant_list(input_line):
    # TODO: Replace hack and improve code
    grant_list = []
    for line in input_line.splitlines():
        if re.search("GRANT", line, re.IGNORECASE):
            grant_list.append(line)
    return grant_list

def split_sql_statement(sql_source):
    dict = {}
    dict["GENSQL_LOOP_LINE"] = []
    #print "*** SQL SOURCE ***"
    #print sql_source
    before_insert_comments = ""
    after_insert = ""
    found_insert = False
    for line in sql_source.splitlines():
        if found_insert == True:
            after_insert = after_insert + line + "\n"
        elif line.startswith("--"):
            before_insert_comments = before_insert_comments + line + "\n"
        elif line.startswith("INSERT"):
            after_insert = line + "\n"
            found_insert = True

    dict["BEFORE_INSERT_COMMENTS"] = before_insert_comments
    dict["INSERT_STATEMENT"] = after_insert

    before_select, after_select = re.split("SELECT", after_insert, 1, flags=re.IGNORECASE)
    select_statement, after_semicolon = re.split("(?<!--);", after_select)
    dict["SELECT_STATEMENT"] = "SELECT " + select_statement
    dict["AFTER_SEMICOLON"] = after_semicolon
    
    for line in select_statement.splitlines():
        if "GENSQL_LOOP_LINE" in line:
            dict["GENSQL_LOOP_LINE"].append(line)

    return dict

def get_loop_args_from_loop_line(run_loop_line):
    if not run_loop_line:
        return {}
    loop_params = run_loop_line.split()
    if (len(loop_params) < 4):
        print "-- SQLRUNNOR - SYNTAX ERROR in RUNLOOP", run_loop_line
        return
    loop_name = loop_params[1]
    loop_start = int(loop_params[2])
    loop_end = int(loop_params[3])
    loop_step = int(loop_params[4])
        
    if (len(loop_params) <= 5):
        loop_num_jobs = int((loop_end - loop_start) / loop_step)
    else:
        loop_num_jobs = int(loop_params[5])
    return {"LOOP_NAME": loop_name, "LOOP_START": loop_start, "LOOP_END": loop_end, "LOOP_STEP": loop_step, "LOOP_NUM_JOBS": loop_num_jobs}

def gen_create_st_sql(table_name, sql_st_dict, dist_style, dist_key, sort_key, order_by, segmented_by):
    create_select = sql_st_dict["SELECT_STATEMENT"]

    #SCB create_st_with_where_fix = re.compile(re.escape("WHERE"), re.IGNORECASE)
    #SCB create_select = create_st_with_where_fix.sub("WHERE 1 = 2 and \n", create_select)
    for gensql_loop_line in sql_st_dict["GENSQL_LOOP_LINE"]:
        #print "*** GENSQL_LOOP_LINE ***", sql_st_dict["GENSQL_LOOP_LINE"]
        create_st_with_loop_fix = re.compile(re.escape(gensql_loop_line), re.IGNORECASE)
        create_select = create_st_with_loop_fix.sub("-- GENSQL COMMENTED OUT" + gensql_loop_line, create_select)

    create_statement = "CREATE TABLE " + table_name + "_TMP\n" \
        + dist_style + " -- GENSQL ADDED\n" \
        + dist_key + " -- GENSQL ADDED\n" \
        + sort_key + " -- GENSQL ADDED\n" \
        + " as \n" \
        + create_select \
        + order_by + " -- GENSQL ADDED\n" \
        + segmented_by + " -- GENSQL ADDED\n" \
        + ";\n"
 
    create_sql = "-- GENSQL Part 1: create TMP table\n\n" \
        + "DROP TABLE IF EXISTS " + table_name + "_TMP;\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n\n" \
        + "-- GENSQL CTAS: " + table_name + "\n" \
        + sql_st_dict["BEFORE_INSERT_COMMENTS"] + "\n" \
        + create_statement \
        + "-- RUNSQL\nCOMMIT;\n-- RUNSQL\n"
    return create_sql

def gen_insert_st_sql(file_name, set_list, run_loop):
    gen_sql_source_line = read_from_file(file_name + ".sql")
    gen_sql_source_set_fixed = replace_with_sets(gen_sql_source_line, set_list)    
    sql_st_dict = split_sql_statement(gen_sql_source_set_fixed)

    loop_args = get_loop_args_from_loop_line(run_loop)

    insert_statement = sql_st_dict["INSERT_STATEMENT"]     

    for gensql_loop_line in sql_st_dict["GENSQL_LOOP_LINE"]:
        #insert_statement = insert_st_with_loop_fix.sub(loop_name + "_start and " + loop_name + "_end" + "-- GENSQL_LOOP_LINE")
        split_loop_line = gensql_loop_line.split()
        new_loop_line = split_loop_line[0] + " " + split_loop_line[1] \
            + " BETWEEN " + loop_args["LOOP_NAME"] + "_start and " + loop_args["LOOP_NAME"] + "_end -- ADDED BY GENSQL"
        insert_st_with_loop_fix = re.compile(re.escape(gensql_loop_line), re.IGNORECASE)
        insert_statement = insert_st_with_loop_fix.sub(new_loop_line, insert_statement)

    insert_sql = "-- GENSQL Part 2: insert loop\n\n" \
        + sql_st_dict["BEFORE_INSERT_COMMENTS"] + "\n" \
        + "-- " + run_loop + "\n" \
        + insert_statement + "\n" \
        + "-- RUNSQL\nCOMMIT;\n-- RUNSQL\n"
    return insert_sql

def gen_cleanup_sql(table_name, no_schema_table_name, vertica_or_redshift, backup_tag, tmp_handling, grant_list):
    cleanup_sql = "-- GENSQL Part 3: clean-up\n\n" 
    if backup_tag <> "":
        cleanup_sql = cleanup_sql \
            + "-- SQLRUNNOR - CREATE BACKUP \n"
        cleanup_sql = cleanup_sql \
            + "-- SQLRUNNOR - Drop Backup\n" \
            + "DROP TABLE IF EXISTS " + table_name + backup_tag + ";\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n\n"
        if tmp_handling == "insert_from_tmp":
            # make a backup of the existing table so we can insert into it from _tmp
            cleanup_sql = cleanup_sql \
                + "-- SQLRUNNOR - INSERT_FROM_TMP: Create Backup Table using Current Table and Insert into it from Current\n" \
                + "CREATE TABLE " + table_name + backup_tag + " AS SELECT * FROM " + table_name + " WHERE 1 = 0;\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n\n" \
                + "INSERT /*+direct*/ INTO " + table_name + backup_tag + " SELECT * FROM " + table_name + ";\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n\n" 
        else:
            # rename the existing table as we will be creating a new table from _tmp
            cleanup_sql = cleanup_sql \
                + "-- SQLRUNNOR - Rename Current table to Backup\n" \
                + "ALTER TABLE " + table_name + " RENAME TO " + no_schema_table_name + backup_tag + ";\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n\n" 
    else:
        cleanup_sql = cleanup_sql \
            + "-- SQLRUNNOR - BACKUP NOT REQUIRED\n"
    if tmp_handling == "insert_from_tmp":    
        cleanup_sql = cleanup_sql \
            + "-- SQLRUNNOR - INSERT_FROM_TMP: Insert from TMP into Current, Drop TMP\n" \
            + "INSERT /*+direct*/ INTO " + table_name + " SELECT * FROM " + table_name + "_TMP;\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n\n" \
            + "DROP TABLE IF EXISTS " + table_name + "_TMP;\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n\n" 
        if vertica_or_redshift == "VERTICA":
            if backup_tag <> "":
                cleanup_sql = cleanup_sql \
                    + "-- SQLRUNNOR - Analyze Statistics for the Current and Backup tables\n" \
                    + "select analyze_statistics('" + table_name + "');\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n" \
                    + "select analyze_statistics('" + table_name + backup_tag + "');\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n"
    else:
        cleanup_sql = cleanup_sql \
            + "-- SQLRUNNOR - Rename TMP to Current\n" \
            + "ALTER TABLE " + table_name + "_TMP RENAME TO " + no_schema_table_name + ";\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n\n" 
        if vertica_or_redshift == "VERTICA":
            cleanup_sql = cleanup_sql \
                   + "-- SQLRUNNOR - Analyze Statistics for the Current Table\n" \
                + "select analyze_statistics('" + table_name + "');\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n"
 
    grant_statement_fix = re.compile(re.escape("GEN_TABLE"), re.IGNORECASE)

    for grant_line in grant_list:
        cleanup_sql = cleanup_sql + "\n" \
            + grant_statement_fix.sub(table_name, grant_line) + \
            "\n\n-- RUNSQL\nCOMMIT;\n-- RUNSQL\n"
    return cleanup_sql
    
def gen_sql(input_line_orig, use_list, set_list, debug_only_option, output_folder):

    gen_sql_file_list = []
    backup_tag = get_backup_tag(use_list)
    vertica_or_redshift = get_vertica_or_redshift(use_list)

    input_line_replaced = replace_with_sets(input_line_orig, set_list)    

    out_table_unreplaced = get_table_name(input_line_orig)
    table_name = get_table_name(input_line_replaced)
    no_schema_table_name = table_name.split('.')[1]

    dist_style = get_dist_style(input_line_replaced)
    dist_key = get_dist_key(input_line_replaced)
    sort_key = get_sort_key(input_line_replaced)

    order_by = get_order_by(input_line_replaced)
    segmented_by = get_segmented_by(input_line_replaced)   
    grant_list = get_grant_list(input_line_replaced)

    run_loop = get_run_loop(input_line_replaced)
    tmp_handling = get_tmp_handling(input_line_replaced)

    merge_list = get_merge_into_tmp_list(input_line_orig)
    
    if not merge_list:
        file_name = get_table_name(input_line_orig)
    else:
        file_name = merge_list[0] # use the first merge file not the name of the output table in manifest

    gen_sql_source_line = read_from_file(file_name + ".sql")
    gen_sql_source_set_fixed = replace_with_sets(gen_sql_source_line, set_list)    

    output_sub_folder = output_folder + "\\" + out_table_unreplaced
    if not os.path.exists(output_sub_folder):
        os.makedirs(output_sub_folder)
       
    sql_st_dict = split_sql_statement(gen_sql_source_set_fixed)

    create_st_sql = gen_create_st_sql(table_name, sql_st_dict, dist_style, dist_key, sort_key, order_by, segmented_by)    
 
    #create_file = output_sub_folder + "\\" + file_name + "_P1.sql"    
    create_file = os.path.join(output_sub_folder, file_name + "_P1.sql")
    write_to_file(create_file, create_st_sql)
    gen_sql_file_list.append(create_file)
            
    #insert_st_with_loop_fix = re.compile(re.escape(sql_st_dict["GENSQL_LOOP_RANGE_PART"]), re.IGNORECASE)
    insert_st_sql = gen_insert_st_sql(file_name, set_list, run_loop)
    
    #insert_file = output_sub_folder + "\\" + file_name + "_P2" + ".sql"    
    insert_file = os.path.join(output_sub_folder, file_name + "_P2.sql")

    write_to_file(insert_file, insert_st_sql)
    if (vertica_or_redshift <> "REDSHIFT"):
        gen_sql_file_list.append(insert_file)
    
    for index, merge_file in enumerate(merge_list, start = 1):
        if index > 1:
            insert_st_sql = gen_insert_st_sql(merge_file, set_list, run_loop)
            #insert_file = output_sub_folder + "\\" + merge_file + "_P2" + ".sql"    
            insert_file = os.path.join(output_sub_folder, merge_file + "_P2.sql")
            write_to_file(insert_file, insert_st_sql)
            if (vertica_or_redshift <> "REDSHIFT"):
                gen_sql_file_list.append(insert_file)       
   
    cleanup_sql = gen_cleanup_sql(table_name, no_schema_table_name, vertica_or_redshift, backup_tag, tmp_handling, grant_list)      

    #cleanup_file = output_sub_folder + "\\" + file_name + "_P3.sql"    
    cleanup_file = os.path.join(output_sub_folder, file_name + "_P3.sql")
    
    write_to_file(cleanup_file, cleanup_sql)
    gen_sql_file_list.append(cleanup_file)
    return gen_sql_file_list

def exec_sql_from_file(config_list, file_name, set_list, debug_only_option):
    returnStr = ""
    print "-- SQLRUNNOR -"
    print "-- SQLRUNNOR - File", file_name
    
    if debug_only_option:
        conn = "conn"
        cur = "cur"
    else:
        conn = connect_db(config_list)
        conn.autocommit = True
        cur = conn.cursor()   
        
    sql_cmds_in_file = read_from_file(file_name)
    sql_cmds_in_file_set_fixed = replace_with_sets(sql_cmds_in_file, set_list)
    sql_cmds_list = sql_cmds_in_file_set_fixed.split("-- RUNSQL\n")
    for sql_cmd in sql_cmds_list:
        if sql_ok(sql_cmd):
            returnStr = run_sql(config_list, sql_cmd, conn, cur, debug_only_option)
    if not debug_only_option:
        conn.close()
    return returnStr

def execute_out_csv(output_file_name, write_or_append, sql_cmd, use_list, conn, cur, debug_only_option):
    file = open(output_file_name, write_or_append)
    csv_hdr_delim = get_csv_hdr_delim(use_list)
    csv_delim = get_csv_delim(use_list)
    out_fetch_size = get_out_fetch_size(use_list)
    
    start_time = time
    returnStr = "\n-- SQLRUNNOR - Started Execution " + start_time.strftime('%Y-%m-%d %H:%M:%S')
    returnStr = returnStr + "\n" + sql_cmd
    if not debug_only_option:
        try:
            cur.execute(sql_cmd)
            output_to_write = ""
            for fld in cur.description:
                if (output_to_write <> ""):
                    output_to_write = output_to_write + csv_hdr_delim
                if (fld <> '\r'):                
                    output_to_write = output_to_write + fld[0]
            output_to_write = output_to_write + "\n"
            file.write(output_to_write)
            
            while True:
                results = cur.fetchmany(out_fetch_size)
                if not results:
                    break
                for row in results: 
                    output_to_write = ""
                    for field in row:
                        if (output_to_write <> ""):
                            output_to_write = output_to_write + csv_delim
                        if (field <> '\r'):
                                if isinstance(field, types.StringTypes):
                                    output_to_write = output_to_write + field.encode('utf-8').strip() 
                                elif (str(field) <> "None"):
                                    output_to_write = output_to_write + str(field) 
                    output_to_write = output_to_write + "\n"
                file.write(output_to_write)
        except pyodbc.Error, err:
            print "exception found"
            returnStr = returnStr + "\n" + "-- SQLRUNNOR - ERROR RUNNING SQL"
            returnStr = returnStr + "\n" + "-- SQLRUNNOR - ERROR: " 
            returnStr = returnStr + str(err)
    file.close()  
    returnStr = returnStr + "\n" + "-- SQLRUNNOR -"
    end_time = time
    returnStr = returnStr + "\n-- SQLRUNNOR - Completed Execution " + end_time.strftime('%Y-%m-%d %H:%M:%S') + "\n"
    return returnStr

def out_csv_from_file(input_line_orig, use_list, set_list, config_list, debug_only_option, output_folder):
    returnStr = ""
    file_name = get_input_sql_file_name(input_line_orig)
	
    out_file_name = replace_with_sets(get_table_name(input_line_orig), set_list)
    out_file_name = get_out_csv_file_name(output_folder, out_file_name)

    sql_cmds_from_file_orig = read_from_file(file_name)
    sql_cmds_in_file_set_fixed = replace_with_sets(sql_cmds_from_file_orig, set_list)    

    #input_line = replace_with_sets(input_line_orig, set_list)    
    if debug_only_option:
        conn = "conn"
        cur = "cur"
    else:
        conn = connect_db(config_list)
        cur = conn.cursor()  

    print "-- SQLRUNNOR -"
    print "-- SQLRUNNOR - Out File", out_file_name
    sql_cmds_list = sql_cmds_in_file_set_fixed.split("-- RUNSQL\n")
    write_or_append = "w"
    for sql_cmd in sql_cmds_list:
        if sql_ok(sql_cmd):
            print sql_cmd
            returnStr = execute_out_csv(out_file_name, write_or_append, sql_cmd, use_list, conn, cur, debug_only_option)
            write_or_append = "a"
    if not debug_only_option:
        conn.close()
    return returnStr
    
def write_to_run_tracking(run_tracking_table, run_tracking, config_list, debug_only_option):
    if run_tracking_table == "":
        return 

    if debug_only_option:
        conn = "conn"
        cur = "cur"
    else:
        conn = connect_db(config_list)
        cur = conn.cursor()   
    
    add_comma = ""
    insert_cdf_run_track = "INSERT /*+direct*/ INTO " + run_tracking_table + "\n  ("
    for field_name, field_value in run_tracking.items():
        insert_cdf_run_track = insert_cdf_run_track + add_comma + field_name 
        add_comma = ", "
    insert_cdf_run_track = insert_cdf_run_track + ") \n  SELECT "  
    add_comma = "\n "
    for field_name, field_value in run_tracking.items():
        insert_cdf_run_track = insert_cdf_run_track + add_comma + str(field_value) + " as " + field_name 
        add_comma = ",\n "
    insert_cdf_run_track = insert_cdf_run_track + ";" 
         
    #print "-- SQLRUNNOR \n" + insert_cdf_run_track
    print execute_sql(insert_cdf_run_track, conn, cur, config_list, debug_only_option)
    if not debug_only_option:
        conn.close()               
                
def execute_sql(sql_cmd, conn, cur, config_list, debug_only_option):
    start_time = time
    returnStr = "\n-- SQLRUNNOR - Started Execution " + start_time.strftime('%Y-%m-%d %H:%M:%S')
    returnStr = returnStr + "\n" + sql_cmd
    if sql_cmd.strip() <> "":
        if not debug_only_option:
            try:
                cur.execute(sql_cmd)
                conn.commit()
            except psycopg2.Error as err:
                returnStr = returnStr + "\n" + "-- SQLRUNNOR - ERROR RUNNING SQL"
                returnStr = returnStr + "\n" + "-- SQLRUNNOR - ERROR: " 
                returnStr = returnStr + str(err)
                send_email_msg(debug_only_option, config_list, returnStr)
            #except pyodbc.Error, err:
            #    returnStr = returnStr + "\n" + "-- SQLRUNNOR - ERROR RUNNING SQL"
            #    returnStr = returnStr + "\n" + "-- SQLRUNNOR - ERROR: " 
            #    returnStr = returnStr + str(err)
            #   send_email_msg(config_list, returnStr)
    returnStr = returnStr + "\n" + "-- SQLRUNNOR -"
    end_time = time
    returnStr = returnStr + "\n-- SQLRUNNOR - Completed Execution " + end_time.strftime('%Y-%m-%d %H:%M:%S') + "\n"
    return returnStr
    
def run_loop(config_list, loop_name, i, loop_step, sql_cmd, debug_only_option):
    returnStr = "-- SQLRUNNOR - Loop: " + loop_name + " = " + str(i) + " " + str(i + loop_step - 1)
    loop_sql_cmd = sql_cmd.replace(loop_name + "_start", str(i))
    loop_sql_cmd = loop_sql_cmd.replace(loop_name + "_end", str(i + loop_step - 1))
    
    if debug_only_option:
        conn = 'conn' 
        cur = 'cur' 
    else:
        conn = connect_db(config_list)
        cur = conn.cursor()  
        
    returnStr = returnStr + execute_sql(loop_sql_cmd, conn, cur, config_list, debug_only_option) 
    if not debug_only_option:
        conn.close()
    
    return returnStr
    
def run_sql(config_list, sql_cmd, conn, cur, debug_only_option):
    pos_run_loop = sql_cmd.find("RUNLOOP")
    if (pos_run_loop >= 0):
        run_loop_line = sql_cmd[pos_run_loop:].splitlines(1)
        print "-- SQLRUNNOR - ", run_loop_line[0]
        loop_args = get_loop_args_from_loop_line(run_loop_line[0])
        
        result = Parallel(n_jobs=loop_args["LOOP_NUM_JOBS"])(delayed(run_loop)(config_list, loop_args["LOOP_NAME"], i, loop_args["LOOP_STEP"], sql_cmd, debug_only_option) for i in range(loop_args["LOOP_START"], loop_args["LOOP_END"], loop_args["LOOP_STEP"]))

        print "-- SQLRUNNOR - LOOP NUM JOBS = ", loop_args["LOOP_NUM_JOBS"]
        
        for line in result:
            print line
        print "-- SQLRUNNOR - Completed Loop:", loop_args["LOOP_NAME"], loop_args["LOOP_START"], loop_args["LOOP_END"], loop_args["LOOP_STEP"]
    else:
        print execute_sql(sql_cmd, conn, cur, config_list, debug_only_option)
    return
           
           
def main(argv):
    input_file = ""
    output_folder = "."
    debug_only_option = False
    print_version_option = True

    try:
        opts, args = getopt.getopt(argv,"hvdi:o:",["ifile=", "ofolder="])
    except getopt.GetoptError:
        print "-- SQLRUNNOR - usage: python -u sqlrunnor.py <-v> <-d> -i <input_file> -o <output_folder>"
        sys.exit(2)
    for opt, arg in opts:
        if opt == "-h":
            print "-- SQLRUNNOR - usage: python -u sqlrunnor.py <-v> <-d> -i <input_file> -o <output_folder>"
            sys.exit()
        elif opt == "-v":
            print_version_option = True
        elif opt == "-d":
            debug_only_option = True
        elif opt in ("-i", "--ifile"):
            input_file = arg
        elif opt in ("-o", "--ofolder"):
            output_folder = arg
            

    sys.stderr.write("SQLRUNNOR - Debug option is %s\n" % debug_only_option)      
    config_list = get_configs()
    
    sys.stderr.write('Running...\n')

    print "-- SQLRUNNOR - Input file is ", input_file
    print "-- SQLRUNNOR - Output folder is ", output_folder
    print "-- SQLRUNNOR - Debug option is %s" % debug_only_option

    if print_version_option:
        print "-- SQLRUNNOR - Version: ", config_list["SQLRUNNOR_VERSION"]    
    
    if not os.path.exists(output_folder):
        os.makedirs(output_folder)
      
    input_to_run = read_from_file(input_file)
       
    input_lines_list = split_manifest_lines(input_to_run)

    use_list = {}    
    set_list = collections.OrderedDict()
    
    if config_list["CONNECTION_TYPE"] == "ODBC":
        uid = config_list["UID"]
    else:
        uid = config_list["USER"]
    
    
    #input_line = input_lines_list[0]
    for i in range(0, len(input_lines_list)):
        input_line_tuple = input_lines_list[i]
        input_line_type = input_line_tuple[0]
        input_line_statement = input_line_tuple[1]

        # TODO: The if # is not needed as we are stripping comments
        if (input_line_type == "#"):
            pass
        elif (input_line_type == "USESQL"):
            input_statement_split = input_line_statement.strip().split('=', 1)           
            use_list[input_statement_split[0].strip()] = replace_with_sets(input_statement_split[1].strip(), set_list)
        elif (input_line_type == "SETSQL"):
            input_statement_split = input_line_statement.strip().split('=', 1)           
            set_list[input_statement_split[0].strip()] = replace_with_sets(input_statement_split[1].strip(), set_list)        
        elif (input_line_type == "GENSQL"):
            run_tracking_table = get_run_tracking_table(use_list)
            run_type = get_run_type(use_list)                    
 
            out_table_name = replace_with_sets(get_table_name(input_line_statement), set_list)
            run_loop = replace_with_sets(get_run_loop(input_line_statement), set_list)
            backup_tag = get_backup_tag(use_list)
            if backup_tag == "":
                backup_table_name = ""
            else:
                backup_table_name = out_table_name + backup_tag

            run_tracking_table = run_tracking_table
            
            run_tracking = {}           
            run_tracking["USER_NAME"] = "'" + uid + "'"
            run_tracking["SW_VER"] = "'" + config_list["SQLRUNNOR_VERSION"] + "'"
            run_tracking["RUN_TYPE"] = "'" +  run_type + "'"
            run_tracking["RUN_LOOP"] = "'" +  run_loop + "'"
            run_tracking["OUT_TABLE_NAME"] = "'" +  out_table_name + "'"
            run_tracking["BACKUP_TABLE_NAME"] = "'" +  backup_table_name + "'"                    
           
            gen_files = gen_sql(input_line_statement, use_list, set_list, debug_only_option, output_folder)
            start_time_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
            start_time_secs = time.time()
           
            for gen_file in gen_files:
               # in the exec_sql_from_file: set_list is empty because we have already done the set
               exec_sql_from_file(config_list, gen_file, {}, debug_only_option) 
            end_time_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
            end_time_secs = time.time()
            run_time_seconds = int(end_time_secs - start_time_secs)
            
            run_tracking["START_TIMESTAMP"] = "'" + start_time_str + "'"
            run_tracking["END_TIMESTAMP"] = "'" + end_time_str + "'"
            run_tracking["RUN_DURATION_SECONDS"] = '%d' % run_time_seconds
            run_tracking["RUN_DURATION_MINUTES"] = '%d' % (run_time_seconds / 60)
            run_tracking["RUN_DURATION_HOURS"] = '%0.2f' % (run_time_seconds * 1.0 / 3600)
            run_tracking["OUT_TABLE_ROW_COUNT"] =  "(select count(*) from " + out_table_name + ")"
    
            write_to_run_tracking(run_tracking_table, run_tracking, config_list, debug_only_option)
            send_email_msg(debug_only_option, config_list, "Completed:\n\nTable: %s\n\n# of seconds %s, # of minutes: %s, # of hours: %s\n" % (out_table_name, run_tracking["RUN_DURATION_SECONDS"], run_tracking["RUN_DURATION_MINUTES"], run_tracking["RUN_DURATION_HOURS"]) )
            
        elif (input_line_type == "EXECSQL"):
            run_tracking_table = get_run_tracking_table(use_list)
            run_type = get_run_type(use_list)                    
 
            out_table_name = replace_with_sets(get_table_name(input_line_statement), set_list)
            
            run_tracking = {}           
            run_tracking["USER_NAME"] = "'" + uid + "'"
            run_tracking["SW_VER"] = "'" + config_list["SQLRUNNOR_VERSION"] + "'"
            run_tracking["RUN_TYPE"] = "'" +  run_type + "'"
            run_tracking["RUN_LOOP"] = "''"
            run_tracking["OUT_TABLE_NAME"] = "'" +  out_table_name + "'"
            run_tracking["BACKUP_TABLE_NAME"] = "''"                    
            start_time_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
            start_time_secs = time.time()

            exec_file_name = input_line_statement + ".sql"
            # in the exec_sql_from_file: use set_list because we have not yet done the set
            exec_sql_from_file(config_list, exec_file_name, set_list, debug_only_option)

            end_time_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
            end_time_secs = time.time()
            run_time_seconds = int(end_time_secs - start_time_secs)
            
            run_tracking["START_TIMESTAMP"] = "'" + start_time_str + "'"
            run_tracking["END_TIMESTAMP"] = "'" + end_time_str + "'"
            run_tracking["RUN_DURATION_SECONDS"] = '%d' % run_time_seconds
            run_tracking["RUN_DURATION_MINUTES"] = '%d' % (run_time_seconds / 60)
            run_tracking["RUN_DURATION_HOURS"] = '%0.2f' % (run_time_seconds * 1.0 / 3600)
            run_tracking["OUT_TABLE_ROW_COUNT"] =  "(select count(*) from " + out_table_name + ")"
    
            write_to_run_tracking(run_tracking_table, run_tracking, config_list, debug_only_option)
            send_email_msg(debug_only_option, config_list, "Completed: %s\n\nTable: %s\n\n# of seconds %s, # of minutes: %s, # of hours: %s\n" % (run_type, out_table_name, run_tracking["RUN_DURATION_SECONDS"], run_tracking["RUN_DURATION_MINUTES"], run_tracking["RUN_DURATION_HOURS"]) )
        elif (input_line_type == "OUTCSV"):
            run_tracking_table = get_run_tracking_table(use_list)
            run_type = get_run_type(use_list)                    
 
            out_table_name = replace_with_sets(get_table_name(input_line_statement), set_list)
            
            run_tracking = {}           
            run_tracking["USER_NAME"] = "'" + uid + "'"
            run_tracking["SW_VER"] = "'" + config_list["SQLRUNNOR_VERSION"] + "'"
            run_tracking["RUN_TYPE"] = "'" +  run_type + "'"
            run_tracking["RUN_LOOP"] = "''"
            run_tracking["OUT_TABLE_NAME"] = "'" +  out_table_name + "'"
            run_tracking["BACKUP_TABLE_NAME"] = "''"                    

            start_time_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
            start_time_secs = time.time()

            out_csv_from_file(input_line_statement, use_list, set_list, config_list, debug_only_option, output_folder)
            end_time_str = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
            end_time_secs = time.time()
            run_time_seconds = int(end_time_secs - start_time_secs)
            
            run_tracking["START_TIMESTAMP"] = "'" + start_time_str + "'"
            run_tracking["END_TIMESTAMP"] = "'" + end_time_str + "'"
            run_tracking["RUN_DURATION_SECONDS"] = '%d' % run_time_seconds
            run_tracking["RUN_DURATION_MINUTES"] = '%d' % (run_time_seconds / 60)
            run_tracking["RUN_DURATION_HOURS"] = '%0.2f' % (run_time_seconds * 1.0 / 3600)
            run_tracking["OUT_TABLE_ROW_COUNT"] =  "(select count(*) from " + out_table_name + ")"
    
            write_to_run_tracking(run_tracking_table, run_tracking, config_list, debug_only_option)
            send_email_msg(debug_only_option, config_list, "Completed:\n\nTable: %s\n\n# of seconds %s, # of minutes: %s, # of hours: %s\n" % (out_table_name, run_tracking["RUN_DURATION_SECONDS"], run_tracking["RUN_DURATION_MINUTES"], run_tracking["RUN_DURATION_HOURS"]) )
        else:
            print "-- SQLRUNNOR Unknown statement", input_line_type, input_line_statement

       
if __name__ == "__main__":
   main(sys.argv[1:])    
   
