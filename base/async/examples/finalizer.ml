open Jane.Std
open Async.Std

let eprintf = Printf.eprintf

let resurrect = ref []

let rec finished x =
  eprintf "finished\n%!";
  resurrect := x :: !resurrect;
  Scheduler.finalize finished x;
;;

let () =
  let s = String.create 10 in
  Scheduler.finalize finished s;
;;

let compact () =
  resurrect := [];
  eprintf "compacting\n%!";
  Gc.compact ();
  eprintf "done compacting\n%!";
;;

let rec loop i =
  if i = 0 then
    shutdown 0
  else
    upon (Clock.after (Time.Span.of_sec 1.)) (fun () ->
      compact ();
      loop (i - 1))
;;

let () = loop 5

let () = never_returns (Scheduler.go ())

