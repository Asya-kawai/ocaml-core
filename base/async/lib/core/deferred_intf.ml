open Core.Std

module Deferred = Basic.Deferred

type how = [ `Parallel | `Sequential ]

module type Deferred_sequence = sig
  type 'a t

  val fold : 'a t -> init:'b -> f:('b -> 'a -> 'b Deferred.t) -> 'b Deferred.t

  (* default [how] is [`Sequential] *)
  val iter       : ?how:how -> 'a t -> f:('a -> unit      Deferred.t) -> unit Deferred.t
  val map        : ?how:how -> 'a t -> f:('a -> 'b        Deferred.t) -> 'b t Deferred.t
  val filter     : ?how:how -> 'a t -> f:('a -> bool      Deferred.t) -> 'a t Deferred.t
  val filter_map : ?how:how -> 'a t -> f:('a -> 'b option Deferred.t) -> 'b t Deferred.t

  val all      : 'a   Deferred.t t -> 'a t Deferred.t
  val all_unit : unit Deferred.t t -> unit Deferred.t
end
