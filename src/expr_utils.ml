open Expr_ds

let entry_error str =
  "Tried to unpack a " ^ str ^ " entry, but it isn't one."

let unpack_fp_entry = function
  | FP_entry x -> x
  | _ -> failwith (entry_error "fp")

let unpack_mod_entry = function
  | MOD_entry x -> x
  | _ -> failwith (entry_error "mod")

let unpack_opdecl_entry = function
  | OPDec_entry x -> x
  | _ -> failwith (entry_error "opdec")

let unpack_opdef_entry = function
  | OPDef_entry x -> x
  | _ -> failwith (entry_error "opdef")

let unpack_thm_entry = function
  | THM_entry x -> x
  | APSUBST_entry x -> failwith "unpacked apsubst instead of thm"
  | FP_entry x -> failwith "unpacked fp instead of thm"
  | MOD_entry x -> failwith "unpacked mod instead of thm"
  | OPDef_entry x -> failwith "unpacked opdef instead of thm"
  | OPDec_entry x -> failwith "unpacked opdec instead of thm"
  | ASSUME_entry x -> failwith "unpacked assume instead of thm"

let unpack_assume_entry = function
  | ASSUME_entry x -> x
  | _ -> failwith (entry_error "assume")

let unpack_apsubst_entry = function
  | APSUBST_entry x -> x
  | _ -> failwith (entry_error "apsubst")

let extract_location expr =
  match expr with
  | E_at { location; level } -> location
  | E_decimal { location; level; } -> location
  | E_label { location; level; } -> location
  | E_let_in { location; level; } -> location
  | E_numeral { location; level; } -> location
  | E_op_appl { location; level; } -> location
  | E_string { location; level; } -> location
  | E_subst_in { location; level; } -> location
  | E_binder {location; level; } -> location
  | E_lambda {location; level; } -> location

let extract_level expr =
  match expr with
  | E_at { location; level } -> level
  | E_decimal { location; level; } -> level
  | E_label { location; level; } -> level
  | E_let_in { location; level; } -> level
  | E_numeral { location; level; } -> level
  | E_op_appl { location; level; } -> level
  | E_string { location; level; } -> level
  | E_subst_in { location; level; } -> level
  | E_binder {location; level; } -> level
  | E_lambda {location; level; } -> level

(** wraps an expression into an assume-prove with empty assumptions *)
let assume_prove_from_expr expr suffices =  {
location = extract_location expr;
level = None;
assumes = [];
new_symbols = [];
prove = expr;
suffices;
boxed = false; (* TODO: check if this is true *)
}
