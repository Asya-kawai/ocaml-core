open Std_internal

module Result = struct

  type 'a t = Rval of 'a | Expt of exn

  let return = function
    | Rval v -> v
    | Expt e -> raise e

  let capture f x =
    try Rval (f x) with
    | Sys.Break as e -> raise e
    | e -> Expt e

end

(* special case of [general] where input type is [unit] *)
let unit f =
  let l = Lazy.lazy_from_fun f in
  (fun () -> Lazy.force l)

let unbounded f =
  let cache = Hashtbl.Poly.create () ~size:0 in
  (fun arg ->
    Result.return begin
      Hashtbl.find_or_add cache arg
        ~default:(fun () -> Result.capture f arg)
    end)

(* the same but with a bound on cache size *)
let lru (type a) ~max_cache_size f =
  let max_cache_size = Int.max 1 max_cache_size in
  let module Cache =
    Hash_queue.Make (struct
      type t = a
      let compare = Pervasives.compare
      let hash = Hashtbl.hash
      (* dead code *)
      let t_of_sexp _ = assert false
      let sexp_of_t _ = assert false
    end)
  in
  let cache = Cache.create () in
  (fun arg ->
    Result.return begin
      match Cache.lookup cache arg with
      | Some result ->
        (* move to back of the queue *)
        Cache.remove_exn cache arg;
        Cache.enqueue_exn cache arg result;
        result
      | None ->
        let result = Result.capture f arg in
        Cache.enqueue_exn cache arg result;
        (* eject least recently used cache entry *)
        if Cache.length cache > max_cache_size then ignore (Cache.dequeue_exn cache);
        result
    end)

let general ?cache_size_bound f =
  match cache_size_bound with
  | None -> unbounded f
  | Some n -> lru ~max_cache_size:n f

TEST_MODULE "lru" = struct
  let count = ref 0  (* number of times f underlying function is run *)
  let f = lru ~max_cache_size:3 (fun i -> incr count; i)

  TEST = f 0 = 0
  TEST = !count = 1

  TEST = f 1 = 1
  TEST = !count = 2

  TEST = f 0 = 0
  TEST = !count = 2

  TEST = f 3 = 3                       (* cache full *)
  TEST = !count = 3

  TEST = f 4 = 4                       (* evict 1 *)
  TEST = !count = 4

  TEST = f 0 = 0
  TEST = !count = 4

  TEST = f 1 = 1                       (* recompute 1 *)
  TEST = !count = 5
end
