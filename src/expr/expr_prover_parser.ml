open Commons
open Expr_ds
open Expr_builtins
open Expr_dereference
open List

type fixity =
  | Standard
  | UnaryPrefix
  | UnaryPostfix
  | BinaryInfix
  | Special of Builtin.builtin_symbol

let match_function term_db = function
  | E_op_appl appl  ->
    (
      let args = appl.operands in
      match appl.operator with
      | FMOTA_op_def (O_user_defined_op uop) ->
        let uopi = Deref.user_defined_op term_db uop in
        Some (uopi.name, args)
      | FMOTA_op_def (O_builtin_op bop) ->
        let bopi = Deref.builtin_op term_db bop in
        Some (bopi.name, args)
      | FMOTA_op_def (O_module_instance _) ->
        None (* TODO: decide what to do in this case *)
      | _ ->  None
    )
  | _ -> None

let match_constant term_db expr =
  match match_function term_db expr with
  | Some (name, []) -> Some name
  | _ -> None

let expr_to_prover term_db expr =
  match match_constant term_db expr with
  | Some "SMT" -> Some SMT
  | Some "LS4" -> Some LS4
  | Some "Isa" -> Some Isabelle
  | Some "Zenon" -> Some Zenon
  | _ -> None

(* TODO: check if the sany parser does not change names *)
let infix_names =
  [
    "!!"; "#"; "##"; "$"; "$$"; "%"; "%%";
    "&"; "&&"; "(+)"; "(-)"; "(.)"; "(/)"; "(\\X)";
    "*"; "**"; "+"; "++"; "-"; "-+->"; "--";
    "-|"; ".."; "..."; "/"; "//"; "/="; "/";
    "::="; ":="; ":>"; "<"; "<:"; "<=>"; "=";
    "=<"; "=>"; "=|"; ">"; ">="; "?";
    "??"; "@@"; ""; "\\/"; "^"; "^^"; "|"; "|-";
    "|="; "||"; "~>"; ".";
    "\\approx"; "\\geq"; "\\oslash"; "\\sqsupseteq";
    "\\asymp"; "\\gg"; "\\otimes"; "\\star"; "\\bigcirc";
    "\\in"; "\\prec"; "\\subset"; "\\bullet"; "\\intersect";
    "\\preceq"; "\\subseteq"; "\\cap"; "\\land"; "\\propto";
    "\\succ"; "\\cdot"; "\\leq"; "\\sim"; "\\succeq"; "\\circ";
    "\\ll"; "\\simeq"; "\\supset"; "\\cong"; "\\lor"; "\\sqcap";
    "\\supseteq"; "\\cup"; "\\o"; "\\sqcup"; "\\union"; "\\div";
    "\\odot"; "\\sqsubset"; "\\uplus"; "\\doteq"; "\\ominus";
    "\\sqsubseteq"; "\\wr"; "\\equiv"; "\\oplus"; "\\sqsupset"
  ]

(* TODO: check if the sany parser does not change names *)
let prefix_names =
  [ "-"; "~"; "\\lnot"; "\\neg"; "[ ]"; "\\< >";
    "DOMAIN" ; "ENABLED" ; "SUBSET" ; "UNCHANGED" ; "UNION";
  ]

let postfix_names = ["$Prime"]

let ternary_names =
  [  "$IfThenElse"  ]

let expand_ternary_name = function
  | "$IfThenElse" -> "IF", "THEN", "ELSE"
  | s -> failwith ("Don't know how to expand infix ternary operator " ^ s )

let extract_binary_args arity name params =
  if (arity = 2) && (mem name infix_names)
  then true else false

let extract_ternary_args arity name params =
  if (arity = 3) && (mem name ternary_names)
  then Some name else None

let extract_mixfix_args arity name params =
  let rec gen_commas suffix = function
    | 2 -> suffix
    | n when n > 2 ->
      let suffix_ = ", " :: suffix in
      gen_commas suffix_ (n-1)
    | _ ->
      failwith "Error in extract mixfix implementation!"
  in
  match name, arity with
  | "$FcnApply", n when n > 0 ->
    Some ("" :: "[" :: (gen_commas ["]"] n))
  | _ -> None

let match_infix_op term_db = function
  | FMOTA_formal_param fp -> false
  | FMOTA_op_def (O_user_defined_op uop) ->
    let uopi = Deref.user_defined_op term_db uop in
    extract_binary_args uopi.arity uopi.name uopi.params
  | FMOTA_op_def (O_builtin_op op) ->
    let opi = Deref.builtin_op term_db op in
    extract_binary_args opi.arity opi.name opi.params
  | FMOTA_op_def _ -> false
  | FMOTA_op_decl opdecl -> false
  | FMOTA_ap_subst_in _ -> false
  | FMOTA_lambda _ -> false

let match_ternary_op term_db = function
  | FMOTA_formal_param fp -> None
  | FMOTA_op_def (O_user_defined_op uop) ->
    let uopi = Deref.user_defined_op term_db uop in
    extract_ternary_args uopi.arity uopi.name uopi.params
  | FMOTA_op_def (O_builtin_op op) ->
    let bopi = Deref.builtin_op term_db op in
    extract_ternary_args bopi.arity bopi.name bopi.params
  | FMOTA_op_def _ -> None
  | FMOTA_op_decl opdecl -> None
  | FMOTA_ap_subst_in _ -> None
  | FMOTA_lambda _ -> None

let match_mixfix_op term_db = function
  | FMOTA_formal_param fp -> None
  | FMOTA_op_def (O_user_defined_op uop) ->
    let uopi = Deref.user_defined_op term_db uop in
    extract_mixfix_args uopi.arity uopi.name uopi.params
  | FMOTA_op_def (O_builtin_op op) ->
    let opi = Deref.builtin_op term_db op in
    extract_mixfix_args opi.arity opi.name opi.params
  | FMOTA_op_def _ -> None
  | FMOTA_op_decl opdecl -> None
  | FMOTA_ap_subst_in _ -> None
  | FMOTA_lambda _ -> None


let extract_fixity name params =
  match name,params with
  | op, [a1] when List.mem op prefix_names -> UnaryPrefix
  | op, [a1] when List.mem op postfix_names -> UnaryPostfix
  | op, [a1; a2] when List.mem op infix_names -> BinaryInfix
  | "$IfThenElse", [a1; a2; a3] -> Special Builtin.IF_THEN_ELSE
  | "$SquareAct", [_; _] -> Special Builtin.SQ_BRACK
  | "$AngleAct", [_; _] -> Special Builtin.ANG_BRACK
  | "$Tuple", _ -> Special Builtin.TUPLE
  | "$FcnApply", _ -> Special Builtin.FUN_APP
  | "$SetEnumerate", _ -> Special Builtin.SET_ENUM
  | op, _ when List.mem op ["$IfThenElse"; "$SquareAct"; "$AngleAct"] ->
    let msg = CCFormat.sprintf "Unknown arity of builtin %s" op in
    failwith msg
  | _, _ -> Standard

let match_fixity_op term_db =  function
  | FMOTA_op_def (O_user_defined_op uop) ->
    let uopi = Deref.user_defined_op term_db uop in
    extract_fixity uopi.name uopi.params
  | FMOTA_op_def (O_builtin_op op) ->
    let opi = Deref.builtin_op term_db op in
    extract_fixity opi.name opi.params
  | FMOTA_formal_param _
  | FMOTA_op_def _
  | FMOTA_op_decl _
  | FMOTA_ap_subst_in _
  | FMOTA_lambda _ -> Standard
