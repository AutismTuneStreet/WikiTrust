(*

Copyright (c) 2008-09 The Regents of the University of California
All rights reserved.

Authors: Luca de Alfaro, Ian Pye, B. Thomas Adler

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. The names of the contributors may not be used to endorse or promote
products derived from this software without specific prior written
permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

 *)

(** This class provides a handle for accessing the database in the on-line 
    implementation. *)

open Online_types;;

(** All the methods uniformly return DB_Not_Found when some desired
    information cannot be read from the database. *)
exception DB_Not_Found;;

(** Raised when a commit fails. *)
exception DB_TXN_Bad;;

(** Represents the revision table in memory *)
type revision_t = {
  rev_id: int; 
  rev_page: int; 
  rev_text_id: int; 
  rev_timestamp: string; 
  rev_user: int; 
  rev_user_text: string;
  rev_is_minor: bool; 
  rev_comment: string
} 

(** This is the type of a vote data *)
type vote_t = {
  vote_time: string;
  vote_page_id: int; 
  vote_revision_id: int;
  vote_voter_id: int;
}

(** This is the type of a signature set *)
type page_sig_t
val empty_page_sigs : page_sig_t

(* If a signatures base path is provided, then we store: 
   At position 0: the sigs of the page.
   At position 1: the deleted chunks of the page. *)
class db : 
  string ->        (* db prefix *)
  Mysql.dbd ->     (* mediawiki db handle *)
  string ->        (* database name *)
  string option -> (* revision base path *)
  string option -> (* signatures base path *)
  string option -> (* colored revisions base path *)
  bool ->          (* debug_mode *)
  object

    (* ================================================================ *)
    (* Disconnect *)
    method close : unit 

    (* ================================================================ *)
    (* Locks. *)

    (** [get_page_lock page_id timeout] gets a lock for page
	[page_id], to guarantee mutual exclusion on the updates for
	page [page_id].  The lock is waited for at most time [timeout]
	seconds.  The function returns [true] if the lock was
	acquired. *)
    method get_page_lock : int -> int -> bool

    (** [is_page_lock_free page_id] checks whether the lock for page
	[page_id] is available (there is no guarantee that somebody
	does not lock the page between this test and a subsequent call
	to [get_page_lock]. *)
    method is_page_lock_free : int -> bool

    (** [release_page_lock page_id] releases the lock for page
	[page_id], to guarantee mutual exclusion on the updates for
	page [page_id]. *)
    method release_page_lock : int -> unit

    (** Start a transaction *)
    method start_transaction : unit

    (** Rollback a transaction *)
    method rollback_transaction : unit 

    (** Commit of transaction *)
    method commit : unit

    (* ================================================================ *)
    (* Global methods. *)

    (** [get_histogram] Returns a histogram showing the number of users 
	at each reputation level *)
    method get_histogram : float array * float
    
    (** write_histogram delta_hist median] increments the db histogram
	of user reputations according to the array [delta_hist], and
	writes that the new median is [median]. *)
    method write_histogram : float array -> float -> unit 

    (** [fetch_last_colored_rev_time req_page_id] returns the timestamp and the 
	revision id of the most recent revision that has been colored.
	If [req_page_id] specifies a page, then only that page is considered.
        Raises DB_Not_Found if no revisions have been colored. *)    
    method fetch_last_colored_rev_time : int option -> string * int
    
    (** [fetch_all_revs_after req_page_id req_rev_id timestamp rev_id
        limit] returns all revs created after the given [timestamp],
        or at the same [timestamp], with revision id at least
        [rev_id], up to the maximim number [limit].  If [req_page_id]
        specifies a page, then only that page is considered.  If
        [req_rev_id] specifies a revision, then that revision is
        included in the result. *)
    method fetch_all_revs_after : int option -> int option -> string -> int -> int -> revision_t list

    (** [fetch_all_revs req_page_id max_revs_to_return] returns a list
	of revisions in the database, in ascending order of timestamp,
	of length at most [max_revs_to_return].  If [req_page_id]
	specifies a page, then only that page is considered. *)
    method fetch_all_revs : int option -> int -> revision_t list

    (** [fetch_unprocessed_votes req_page_id n_events] returns at most [n_events]
	unprocessed votes, starting from the oldest unprocessed
	vote.
	If [req_page_id] specifies a page, then only that page is considered. *)
    method fetch_unprocessed_votes : int option -> int -> vote_t list

    (** [mark_vote_as_processed (revision_id: int) (voter_id : int)]
	marks a vote as processed. *)
    method mark_vote_as_processed : int -> int -> unit

    (* ================================================================ *)
    (* Page methods.  We assume we have a lock on the page when calling
       these methods. *)

  (** [write_page_info page_id chunk_list p_info] writes that the page
      with id [page_id] is associated with the "dead" strings of text
      [chunk1], [chunk2], ..., where [chunk_list = [chunk1, chunk2,
      ...] ].  The chunk_list contains text that used to be present in
      the article, but has been deleted.  The function also writes the
      rest of the page information [p_info]. *)
    method write_page_chunks_info : int -> Online_types.chunk_t list -> Online_types.page_info_t -> unit

(** [write_page_info page_id p_info] writes that the page [page_id]
    has associated information [p_info].  The list of deleted chunks
    of the page is not modified. *)
    method write_page_info : int -> Online_types.page_info_t -> unit

  (** [read_page_info page_id] returns the list of dead chunks associated
      with the page [page_id], along with the page information. *)
    method read_page_info : int -> (Online_types.chunk_t list) * Online_types.page_info_t

    (** [fetch_col_revs page_id timestamp rev_id fetch_limit] returns a
	cursor that points to at most [fetch_limit] colored revisions of page
	[page_id] with time and revision immediately preceding 
        [timestamp], and [rev_id]. *)
    method fetch_col_revs : int -> timestamp_t -> int -> int -> Mysql.result
      
    (** [get_latest_col_rev_id page_id] returns the revision id of the most 
	recent colored revision of page [page_id]. *)
    method get_latest_col_rev_id : int -> int
    (** [get_latest_rev_id page_title] returns the revision id of the most 
	recent revision of page [page_title]. *)
    method get_latest_rev_id : string -> int

    (** [get_page_id page_title] returns the page id of the named page *)
    method get_page_id : string -> int

    (** [get_page_title page_id] returns the page title of the named page *)
    method get_page_title : int -> string

    (** [read_page_sigs page_id] reads and returns the sigs for page [page_id]. *)
    method read_page_sigs : int -> page_sig_t

    (** [write_page_sigs page_id sigs] writes that the sigs 
	page [page_id] are [sigs]. *)
    method write_page_sigs : int -> page_sig_t -> unit

    (* ================================================================ *)
    (* Revision methods.  We assume we have a lock on the page to which 
       the revision belongs when calling these methods. *)

    (** [revision_needs_coloring page_id rev_id] checks whether a revision has already been 
	colored for trust. *)
    method revision_needs_coloring : int -> int -> bool

    (** [read_wikitrust_revision rev_id] reads a revision from the 
	wikitrust_revision table. *)
    method read_wikitrust_revision : int -> (revision_t * qual_info_t)

  (** [write_wikitrust_revision revision_info quality_info]
      writes the wikitrust data associated with a revision. *)
    method write_wikitrust_revision : 
      revision_t -> qual_info_t -> unit

    (** [read_revision_quality rev_id] reads the wikitrust quality
	information of revision_id *)
    method read_revision_quality : int -> qual_info_t

    (** [fetch_rev_timestamp rev_id] returns the timestamp of revision [rev_id] *)
    method fetch_rev_timestamp : int -> timestamp_t

    (** [get_rev_text page_id rev_id text_id] returns the text
        associated with text id [text_id].  The [page_id] and [rev_id]
        are needed in case the filesystem interface is used. *)
    method read_rev_text : int -> int -> int -> string 

    (** [write_colored_markup page_id rev_id markup] writes,
	in a table with columns by (revision id, string), that the
	string [markup] is associated with the revision with id
	[rev_id] of page [page_id].  The [markup] represents the main
	text of the revision, annotated with trust and origin
	information; it is what the "colored revisions" of our batch
	demo are.  When visitors want the "colored" version of a wiki
	page, it is this chunk they want to see.  Therefore, it is
	very important that this chunk is easy and efficient to read.
	A filesystem implementation, for very large wikis, may be
	used.  *)
    method write_colored_markup : int -> int -> string -> unit 

    (** [read_colored_markup page_id rev_id] reads the text markup of
	a revision with id [rev_id] for page [page_id].  The markup is
	the text of the revision, annontated with trust and origin
	information. *)
    method read_colored_markup : int -> int -> string

    (** [write_trust_origin_sigs page_id rev_id words trust origin
	sigs] writes that the revision [rev_id] of [page_id] is
	associated with [words], [trust], [origin], and [sigs]. *)
    method write_words_trust_origin_sigs : 
      int -> int -> page_sig_t ->
      string array -> 
      float array -> 
      int array -> 
      string array ->
      Author_sig.packed_author_signature_t array -> unit 

    (** [read_words_trust_origin_sigs page_id rev_id] reads the words,
	trust, origin, and author sigs for the revision [rev_id] of
	page [page_id] from the [wikitrust_sigs] table. *)
    method read_words_trust_origin_sigs : 
      int -> int -> page_sig_t ->
      (string array * float array * int array * string array * Author_sig.packed_author_signature_t array)

    (** [delete_author_sigs page_id rev_id] removes from the db the author 
	signatures for [rev_id] of [page_id]. *)
    method delete_author_sigs : int -> int -> page_sig_t -> unit

    (** [update_queue_page page_title] updates the default page_id to a real 
    one. *)
    method update_queue_page : string -> int -> int

    (* ================================================================ *)
    (* User methods. *)

    (** [inc_rep uid delta] increments the reputation of user [uid] by [delta] in
	a single operation, so to avoid database problems. *)
    method inc_rep : int -> float -> unit

    (** [get_rep uid] gets the reputation of user [uid], from a table 
	relating user ids to their reputation *)
    method get_rep : int -> float

    (** [get_user_id name] gets the user id for the user with the given user name *)
    method get_user_id : string -> int

    (** [write_user_id uid user_name] writes that the user with id [uid] 
	has name [user_name]. *) 
    method write_user_id : int -> string -> unit

    (* ================================================================ *)
    (* Debugging. *)

    (** Totally clear out the db structure -- THIS IS INTENDED ONLY FOR UNIT
    TESTING *)
    method delete_all : bool -> unit

    (* ================================================================ *)
    (* Voting. *)

    (** Add the vote to the db *)
    method vote : vote_t -> unit

    (* ================================================================ *)
    (* Server System. *)

  (** [fetch_work_from_queue max_to_get n_retries] gets the
      list of page ids and titles that have to be brought up to date. 
      It also marks those pages as "processing", so that
      subsequent requests do not return the same revisions.  This code
      contains a transaction start / commit pair.  [max_to_get] is the
      maximum number of results to get; [n_retries] is the number of
      times the start / commit pair is used. *)
    method fetch_work_from_queue : int -> int -> (int * string) list

    (** [mark_page_to_process page_id page_title] specifies that a page must be brought
	up to date, due to a vote or a new revision. *)
    method mark_page_to_process : int -> string -> unit
      
    (** [mark_page_as_processed page_id] marks that a page has ben processed. *)
    method mark_page_as_processed : int -> unit
      
    (** [mark_page_as_unprocessed page_id] marks that a page has not been fully processed. *)
    method mark_page_as_unprocessed : int -> unit

    (** [erase_cached_rev_text page_id rev_id rev_time_string] erases the cached text of all
	revisions of [page_id] prior and including the ones for [rev_id] and [rev_time_string]. *)
    method erase_cached_rev_text : int -> int -> string -> unit

    (* ================================================================ *)
    (* WikiMedia Api *)
    (** [write_page page_to_add] adds adds the given data to the page
	table of the database.  It can be used to import data from the
	mediawiki api and store it locally.  *)
    method write_page : wiki_page_t -> unit

    (** [write_revision revision_to_add] adds the given data to the
	revision and text tables of the database.  It can be used to
	import data from the mediawiki api and store it locally.  *)
    method write_revision : wiki_revision_t -> unit

  end


(** [create_db use_exec_api db_prefix mediawiki_dbh db_name
    rev_base_path sig_base_path colored_base_path debug_mode]
    returns a db of the appropriate type, according to whether we are using the exec api 
    or not.  [db_prefix] is the prefix of the db tables; [mediawiki_dbh] is the db handle,
    [db_name] is the name of the database (used to ensure lock uniqueness),
    the base paths point to the location of filesystem storage of revision information,
    and [debug_mode] is a flag to facilitate debugging. *)
val create_db :
  bool ->          (* use_exec_api *)
  string ->        (* db prefix *)
  Mysql.dbd ->     (* mediawiki db handle *)
  string ->        (* database name *)
  string option -> (* revision base path *)
  string option -> (* signatures base path *)
  string option -> (* colored revisions base path *)
  bool ->          (* debug_mode *)
  db
