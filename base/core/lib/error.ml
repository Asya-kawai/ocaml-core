open Sexplib.Std
open Bin_prot.Std

module Conv = Sexplib.Conv

(* Note that this module is trying to minimize dependencies on modules in Core, so as to
   allow Error (and Or_error) to be used in various places.  Please avoid adding new
   dependencies. *)
module List = Core_list
module Sexp = Core_sexp

let concat ?(sep="") l = String.concat sep l

type sexp = Sexp.t = Atom of string | List of sexp list (* constructor import *)

module Message = struct
  type t =
  | Could_not_construct of Sexp.t
  | String of string
  | Sexp of Sexp.t
  | Tag_string of string * string
  | Tag_sexp of string * Sexp.t
  | Tag_t of string * t
  | Tag_arg of string * Sexp.t * t
  | Of_list of int option * t list
  with bin_io, sexp


  let rec to_strings_hum t ac =
    match t with
    | Could_not_construct sexp ->
      "could not construct error: " :: Sexp.to_string_hum sexp :: ac
    | String string -> string :: ac
    | Sexp sexp -> Sexp.to_string_hum sexp :: ac
    | Tag_string (tag, string) -> tag :: ": " :: string :: ac
    | Tag_sexp (tag, sexp) -> tag :: ": " :: Sexp.to_string_hum sexp :: ac
    | Tag_t (tag, t) -> tag :: ": " :: to_strings_hum t ac
    | Tag_arg (tag, sexp, t) ->
      tag :: ": " :: Sexp.to_string_hum sexp :: ": " :: to_strings_hum t ac
    | Of_list (trunc_after, ts) ->
      let ts =
        match trunc_after with
        | None -> ts
        | Some max ->
          let n = List.length ts in
          if n <= max then
            ts
          else
            List.take ts max @ [ String (Printf.sprintf "and %d more errors" (n - max)) ]
      in
      List.fold (List.rev ts) ~init:ac ~f:(fun ac t ->
        to_strings_hum t (if List.is_empty ac then ac else ("; " :: ac)))
  ;;

  let to_string_hum t = concat ~sep:"" (to_strings_hum t [])

  let rec to_sexps_hum t ac =
    match t with
    | Could_not_construct _ as t -> sexp_of_t t :: ac
    | String string -> Atom string :: ac
    | Sexp sexp -> sexp :: ac
    | Tag_string (tag, string) -> List [ Atom tag; Atom string ] :: ac
    | Tag_sexp (tag, sexp) -> List [ Atom tag; sexp ] :: ac
    | Tag_t (tag, t) -> List (Atom tag :: to_sexps_hum t []) :: ac
    | Tag_arg (tag, sexp, t) -> List (Atom tag :: sexp :: to_sexps_hum t []) :: ac
    | Of_list (_, ts) ->
      List.fold (List.rev ts) ~init:ac ~f:(fun ac t -> to_sexps_hum t ac)
  ;;

  let to_sexp_hum t =
    match to_sexps_hum t [] with
    | [sexp] -> sexp
    | sexps -> Sexp.List sexps
  ;;
end

open Message

type t = Message.t Lazy.t

type error_ = t


(* We use [protect] to guard against exceptions raised by user-supplied functons, so
   that failure to produce an error message doesn't interfere with other error messages. *)
let protect f = try f () with exn -> Message.Could_not_construct (Exn.sexp_of_t exn)

let to_message t = protect (fun () -> Lazy.force t)

let of_message message = lazy message

let sexp_of_t t = Message.sexp_of_t (to_message t)

let t_of_sexp sexp = of_message (Message.t_of_sexp sexp)

let to_string_hum t = Message.to_string_hum (to_message t)

let to_sexp_hum t = Message.to_sexp_hum (to_message t)

include Bin_prot.Utils.Make_binable (struct
  module Binable = Message
  type t = error_
  let to_binable = to_message
  let of_binable = of_message
end)

let of_lazy l = lazy (protect (fun () -> String (Lazy.force l)))

let of_string error = lazy (String error)

let of_thunk f = lazy (protect (fun () -> String (f ())))

let string_arg tag string_of_x x =
  lazy (protect (fun () -> Tag_string (tag, string_of_x x)))
;;

let create tag x sexp_of_x = lazy (protect (fun () -> Tag_sexp (tag, sexp_of_x x)))

let arg tag sexp_of_x x = create tag x sexp_of_x

let tag t tag = lazy (Tag_t (tag, to_message t))

let tag_arg t tag sexp_of_x x =
  lazy (protect (fun () -> Tag_arg (tag, sexp_of_x x, to_message t)))
;;

let of_list ?trunc_after ts = lazy (Of_list (?trunc_after, List.map ts ~f:to_message))

exception Error of t with sexp

let of_exn = function
  | Error t -> t
  | exn -> lazy (Sexp (Exn.sexp_of_t exn))
;;

let raise t = raise (Error t)

TEST_MODULE "error" = struct
  TEST = to_string_hum (tag (of_string "b") "a") = "a: b"
  TEST = to_string_hum (of_list (List.map ~f:of_string [ "a"; "b"; "c" ])) = "a; b; c"

  let round t =
    let sexp = sexp_of_t t in
    sexp = sexp_of_t (t_of_sexp sexp)
  ;;

  TEST = round (of_string "hello")
  TEST = round (of_thunk (fun () -> "hello"))
  TEST = round (string_arg "tag" string_of_int 13)
  TEST = round (arg "tag" <:sexp_of< int >> 13)
  TEST = round (tag (of_string "hello") "tag")
  TEST = round (tag_arg (of_string "hello") "tag" <:sexp_of< int >> 13)
  TEST = round (of_list [ of_string "hello"; of_string "goodbye" ])
end

(* yminsky: benchmarks

   open Core.Std
   module Bench = Core_extended.Bench

   let () =
   Bench.bench ~print:true (fun () ->
   let x = 33 in
   ignore (sprintf "%d" x)) ()
   |! Bench.print_costs

   let () =
   Bench.bench ~print:true (fun () ->
   let x = 33 in
   let closure = (fun () -> sprintf "%d" x) in
   ignore (if 3 = 4 then closure () else "")) ()
   |! Bench.print_costs

   Here are the bench results themselves:

   calculating cost of timing measurement: 260 ns
   calculating minimal measurable interval: 1000 ns
   determining number of runs per sample: 1048576
   stabilizing GC: done
   calculating the cost of a full major sweep: 1431398 ns
   running samples (estimated time 59 sec)
   ....................................................................................................
   mean run time + mean gc time: 568 ns
   warning: max run time is more than 5% away from mean
   calculating cost of timing measurement: 258 ns
   calculating minimal measurable interval: 1000 ns
   determining number of runs per sample: 134217728
   stabilizing GC: done
   calculating the cost of a full major sweep: 1484784 ns
   running samples (estimated time 75 sec)
   ....................................................................................................
   mean run time + mean gc time: 5 ns
   warning: max run time is more than 5% away from mean

*)
