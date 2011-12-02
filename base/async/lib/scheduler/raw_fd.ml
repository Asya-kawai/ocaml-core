open Core.Std
open Import

module File_descr = Unix.File_descr

module Kind = struct
  type t =
  | Char
  | Fifo
  | File
  | Socket of [ `Unconnected | `Bound | `Passive | `Active ]
  with sexp_of
end

module State = struct
  (* [State] is is used to keep track of when the file descriptor is closed, or being
     used.  Here are the allowed transitions.

     Open --> Close_requested --> Closed
     |
     ---> Replaced *)
  type t =
  (* [Close_requested] indicates that [Fd.close t] has been called, but that we haven't
     yet started the close() syscall, because there are still active syscalls using the
     file descriptor.  The argument is a function that will do the close syscall,
     and return when it is complete. *)
  | Close_requested of (unit -> unit Deferred.t)
  (* [Closed] indicates that there are no more active syscalls and we have
     started the close() syscall. *)
  | Closed
  (* [Open] is the initial state of a file descriptor, and the normal state when it
     is in use.  It indicates that it has not not yet been closed or replaced. *)
  | Open
  (* [Replaced] indicates a file descriptor that is no longer in use in this [Fd.t] and
     has been put in another one. *)
  | Replaced
  with sexp_of

  let transition_is_allowed t t' =
    match t, t' with
    | Open, (Close_requested _ | Replaced)
    | Close_requested _, Closed
      -> true
    | _ -> false
  ;;

  let is_open = function
    | Close_requested _ | Closed | Replaced -> false
    | Open -> true
  ;;
end

module T = struct
  type ready_to_result = [ `Ready | `Bad_fd | `Closed | `Interrupted ]
  with sexp_of

  type t =
    { name : string; (* for prettiness when debugging *)
      file_descr : File_descr.t;
      kind : Kind.t;
      (* [supports_nonblock] reflects whether the file_descr supports nonblocking
         system calls (read, write, etc.). *)
      supports_nonblock : bool;
      (* [have_set_nonblock] is true if we have called [Unix.set_nonblock file_descr],
         which we must do before making any system calls that we expect to not block. *)
      mutable have_set_nonblock : bool;
      mutable state : State.t;
      mutable num_active_syscalls : int;
      (* [close_finished] becomes determined after the file descriptor has been closed
         and the underlying close() system call has finished. *)
      close_finished : unit Ivar.t;
      (* [ready_to] holds options that are [Some] if [file_descr] is being watched by
         the file-descr watcher for read/write.  They will become determined and cleared
         (set to [None]) when we decide to stop watching them or the file-descr watcher
         reports their disposition (ready or bad). *)
      ready_to : ready_to_result Ivar.t option Read_write.Mutable.t;
    }
  with fields, sexp_of
end

include T

let equal (t : t) t' = phys_equal t t'

let invariant t =
  try
    assert (t.num_active_syscalls >= 0);
    let module S = State in
    begin match t.state with
    | S.Closed | S.Replaced ->
      assert (t.num_active_syscalls = 0);
      assert (Read_write.for_all t.ready_to ~f:Option.is_none);
    | S.Close_requested _ | S.Open -> ()
    end;
    begin match t.state with
    | S.Closed -> ()
    | S.Close_requested _ | S.Open | S.Replaced ->
      assert (Ivar.is_empty t.close_finished)
    end;
    Read_write.iter t.ready_to ~f:(function
      | None -> ()
      | Some ivar ->
        assert (t.num_active_syscalls > 0);
        assert (Ivar.is_empty ivar));
  with
  | exn -> fail "invariant failed" (exn, t) <:sexp_of< exn * t >>
;;

let ready_to t read_or_write = Read_write.get t.ready_to read_or_write

let set_ready_to t read_or_write opt = Read_write.set t.ready_to read_or_write opt

let inc_num_active_syscalls t =
  let module S = State in
  match t.state with
  | S.Close_requested _ | S.Closed | S.Replaced -> `Already_closed
  | S.Open ->
    t.num_active_syscalls <- t.num_active_syscalls + 1;
    `Ok
;;

let set_state t new_state =
  if State.transition_is_allowed t.state new_state then
    t.state <- new_state
  else
    fail "disallowed state transition" (t, new_state) <:sexp_of< t * State.t >>
;;

let is_open t = State.is_open t.state

let is_closed t = not (is_open t)

let set_nonblock_if_necessary t =
  if not t.supports_nonblock then
    fail "set_nonblock_if_necessary called on fd that does not support nonblock" t
    <:sexp_of< t >>;
  if not t.have_set_nonblock then begin
    Unix.set_nonblock t.file_descr;
    t.have_set_nonblock <- true;
  end;
;;

let with_file_descr ?(nonblocking = false) t f =
  if is_closed t then
    `Already_closed
  else begin
    try
      if nonblocking then set_nonblock_if_necessary t;
      `Ok (f t.file_descr)
    with exn -> `Error exn
  end;
;;

let with_file_descr_exn ?nonblocking t f =
  match with_file_descr t f ?nonblocking with
  | `Ok a -> a
  | `Already_closed -> fail "already closed" t <:sexp_of< t >>
  | `Error exn -> raise exn
;;

let syscall ?nonblocking t f =
  with_file_descr t ?nonblocking (fun file_descr ->
    Result.raise_error (Syscall.syscall (fun () -> f file_descr)))
;;

let syscall_exn ?nonblocking t f =
  match syscall t f ?nonblocking with
  | `Ok a -> a
  | `Already_closed -> fail "already closed" t <:sexp_of< t >>
  | `Error exn -> raise exn
;;
