(* This is a webserver built from the Netplex and Nethttpd components.
 * It is configured in the netplex.cfg file. 
 * Note: start program with option "-conf netplex.cfg" 
 * The basic code is copied from the nethttpd example.
 *)

open Netcgi1_compat.Netcgi_types;;
open Printf;;
open Mysql;;
open Online_db;;

(* Mediawiki DB *)
let mw_db_user = ref "wikiuser"
let set_mw_db_user u = mw_db_user := u
let mw_db_pass = ref ""
let set_mw_db_pass p = mw_db_pass := p
let mw_db_name = ref "wikidb"
let set_mw_db_name d = mw_db_name := d
let mw_db_host = ref "localhost"
let set_mw_db_host d = mw_db_host := d
let mw_db_port = ref 3306
let set_mw_db_port d = mw_db_port := d
let db_prefix = ref ""
let set_db_prefix d = db_prefix := d 
let dump_db_calls = ref false

let not_found_text_token = "TEXT_NOT_FOUND"

let dbh = ref None

let text = Netencoding.Html.encode_from_latin1;;
(* This function encodes "<", ">", "&", double quotes, and Latin 1 characters 
 * as character entities. E.g. text "<" = "&lt;", and text "�" = "&auml;"
 *)

(* Return colored markup *)
let generate_text_page (cgi : Netcgi.cgi_activation) (rev_id : int) =
  let out = cgi # out_channel # output_string in
    match !dbh with
      | Some db -> ( 
	  let colored_text = try (db # read_colored_markup rev_id) 
	  with Online_db.DB_Not_Found -> ((db # mark_to_color rev_id);
					  not_found_text_token) in
	    out (text (colored_text))
	)
      | None -> out "DB not initialized"
;;  

(* Return information about an incorrect request. *)
let generate_help_page (cgi : Netcgi.cgi_activation) =
  let out = cgi # out_channel # output_string in
    out not_found_text_token
;;

(* Record that a vote happened. *)
let generate_vote_page (cgi : Netcgi.cgi_activation) (rev_id : int) 
    (page_id : int) (user_id : int) (v_time : string) =
  let out = cgi # out_channel # output_string in
  match !dbh with
    | Some db -> ( 
	let vote = {
	  vote_time=(Mysql.escape v_time);
	  vote_page_id=page_id;
	  vote_revision_id=rev_id;
	  vote_voter_id=user_id;
	} in
	let res = try (db # vote vote; "good") with 
	    Online_db.DB_TXN_Bad -> "bad" in 
	  out res
      )
    | None -> out "DB not initialized"
;;

let generate_page (cgi : Netcgi.cgi_activation) =
  (* Check which page is to be displayed. This is contained in the CGI
   * argument "page".
   *)
  match cgi # argument_value "vote" with
    | "" -> (
	match cgi # argument_value "rev" with
	  | "" ->
	      generate_help_page cgi
	  | _ -> (
	      let rev_id = try (int_of_string 
				  (cgi # argument_value "rev")) with
		  int_of_string -> -1 in
		if rev_id < 0 then generate_help_page cgi else
		  generate_text_page cgi rev_id
	    )
      )
    | _ -> (
	let rev_id = try (int_of_string 
			    (cgi # argument_value "rev")) with
	    int_of_string -> -1 in
	let page_id = try (int_of_string 
			     (cgi # argument_value "page")) with
	    int_of_string -> -1 in
	let user_id = try (int_of_string 
			     (cgi # argument_value "user")) with
	    int_of_string -> -1 in
	let time_str = (cgi # argument_value "time") in
	  generate_vote_page cgi rev_id page_id user_id time_str
      )
;;

let process2 (cgi : Netcgi.cgi_activation) =
  (* The [try] block catches errors during the page generation. *)
  try
    (* Set the header. The header specifies that the page must not be
     * cached. This is important for dynamic pages called by the GET
     * method, otherwise the browser might display an old version of
     * the page.
     * Furthermore, we set the content type and the character set.
     * Note that the header is not sent immediately to the browser because
     * we have enabled HTML buffering.
     *)
    cgi # set_header 
      ~cache:`No_cache 
      ~content_type:"text/plain; charset=\"iso-8859-1\""
      ();

    generate_page cgi;

    (* After the page has been fully generated, we can send it to the
     * browser. 
     *)
    cgi # out_channel # commit_work();
  with
      error ->
	(* An error has happened. Generate now an error page instead of
	 * the current page. By rolling back the output buffer, any 
	 * uncomitted material is deleted.
	 *)
	cgi # out_channel # rollback_work();

	(* We change the header here only to demonstrate that this is
	 * possible.
	 *)
	cgi # set_header 
	  ~status:`Forbidden                  (* Indicate the error *)
	  ~cache:`No_cache 
	  ~content_type:"text/plain; charset=\"iso-8859-1\""
	  ();

        cgi # out_channel # output_string "While processing the request an O'Caml exception has been raised:\n";
        cgi # out_channel # output_string ("" ^ text(Printexc.to_string error) ^ "\n");

	(* Now commit the error page: *)
	cgi # out_channel # commit_work()
;;


let process1 (cgi : Netcgi1_compat.Netcgi_types.cgi_activation) =
  let cgi' = Netcgi1_compat.Netcgi_types.of_compat_activation cgi in
  process2 cgi'


(**********************************************************************)
(* Create the webserver                                               *)
(**********************************************************************)


let start() =
  let (opt_list, cmdline_cfg) = Netplex_main.args() in

  let use_mt = ref false in

  let opt_list' =
    [ ("-mt", Arg.Set use_mt,
      "  Use multi-threading instead of multi-processing");
      ("-db_prefix", Arg.String set_db_prefix, "<string>: Database table prefix (default: none)");
      ("-db_user", Arg.String set_mw_db_user, "<string>: Mediawiki DB username (default: wikiuser)");
      ("-db_name", Arg.String set_mw_db_name, "<string>: Mediawiki DB name (default: wikidb)");
      ("-db_pass", Arg.String set_mw_db_pass, "<string>: Mediawiki DB password");
      ("-db_host", Arg.String set_mw_db_host, "<string>: Mediawiki DB host (default: localhost)");
      ("-db_port", Arg.Int set_mw_db_port,    "<int>: Mediawiki DB port (default: 3306)");
      ("-dump_db_calls", Arg.Set dump_db_calls, ": Writes to the db log all database calls.  This is very verbose; use only for debugging.");
    ] @ opt_list in

  Arg.parse 
    opt_list'
    (fun s -> raise (Arg.Bad ("Don't know what to do with: " ^ s)))
    "usage: netplex [options]";

    (* Prepares the database connection information *)
    let mediawiki_db = {
      dbhost = Some !mw_db_host;
      dbname = Some !mw_db_name;
      dbport = Some !mw_db_port;
      dbpwd  = Some !mw_db_pass;
      dbuser = Some !mw_db_user;
    } in
    dbh := Some (new Online_db.db !db_prefix mediawiki_db None !dump_db_calls);

  let parallelizer = 
    if !use_mt then
      Netplex_mt.mt()     (* multi-threading *)
    else
      Netplex_mp.mp() in  (* multi-processing *)
  let trust_store =
    { Nethttpd_services.dyn_handler = (fun _ -> process1);
      dyn_activation = Nethttpd_services.std_activation `Std_activation_buffered;
      dyn_uri = None;                 (* not needed *)
      dyn_translator = (fun _ -> ""); (* not needed *)
      dyn_accept_all_conditionals = false;
    } in
  let nethttpd_factory = 
    Nethttpd_plex.nethttpd_factory
      ~handlers:[ "trust", trust_store ]
      () in
  Netplex_main.startup
    parallelizer
    Netplex_log.logger_factories   (* allow all built-in logging styles *)
    Netplex_workload.workload_manager_factories (* ... all ways of workload management *)
    [ nethttpd_factory ]           (* make this nethttpd available *)
    cmdline_cfg
;;

Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
start();;
