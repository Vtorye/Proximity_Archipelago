class_name StockReservation
extends RefCounted
## A claim on stock, consumed or released exactly once by the owning inventory.
var id: int
var type: ResourceType
var amount: int
var active := true
