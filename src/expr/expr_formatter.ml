open Commons
open Expr_ds
open Expr_builtins
open Expr_visitor
open Expr_utils
open Expr_dereference
open Util
open Expr_prover_parser
open List
open Format

type nesting = Module | Expression | ProofStep of int | By
(* We need to pass on the formatter, the contect for unfolding references and a
   flag if to unfold *)
type fc = Format.formatter * term_db * bool * nesting * int

(* these are extractors for the accumulator type  *)
let ppf     ( ppf, _, _, _, _ ) = ppf
let tdb     ( _, db, _, _, _ ) = db
let undef   ( _, _, expand, _, _ ) = expand
let nesting ( _, _, _, n, _ ) = n
let ndepth  ( _, _, _,  _, n ) = n


(* sets the expand flag of the accumulator *)
let set_expand (x,y,_,n, d) v = (x,y,v,n,d)

(* sets the expand flag of the first accumulator the the expand flag of the
   second accumulator *)
let reset_expand (x,y,_,n,d) (_,_,v,_,_) = (x,y,v,n,d)

(* modifies the accumulator to turn on definition expansion *)
let enable_expand x = set_expand x true

(* modifies the accumulator to turn off definition expansion *)
let disable_expand x = set_expand x false


let set_nesting (x,y,z,_,u) n = (x,y,z,n,u)
let reset_nesting x (_,_,_,n,_) = set_nesting x n
let nest_module x = set_nesting x Module
let nest_expr x = set_nesting x Expression
let nest_proof x n = set_nesting x (ProofStep n)
let nest_by x = set_nesting x By

let set_ndepth (x,y,z,n,d) depth = (x,y,z,n,depth)
let reset_ndepth x (_,_,_,_,d) = set_ndepth x d
let inc_ndepth x = set_ndepth x ((ndepth x) + 1)


let comma_formatter channel () =
  fprintf channel ", ";
  ()
let newline_formatter channel () =
  fprintf channel "@,";
  ()
let empty_formatter channel () =
  fprintf channel "";
  ()

(* folds the function f into the given list, but extracts the formatter from
   the accumulator and prints the string s after all but the last elements.  *)
let rec ppf_fold_with ?str:(s=comma_formatter) f acc = function
  | [x] ->
    f acc x
  | x::xs ->
    let y = f acc x in
    fprintf (ppf y) "%a" s ();
    ppf_fold_with ~str:s f y xs
  | [] -> acc

(** encloses the given string with parenthesis. can be used as a %a
    argument in a formatter.  *)
let ppf_parens ppf x = fprintf ppf "(%s)" x
(** encloses the given string with a formatting box. can be used as a %a
    argument in a formatter.  *)
let ppf_box ppf x = fprintf ppf "@[%s@]" x
(** prints the given string as it is. can be used as a %a
    argument in a formatter.  *)
let ppf_ident ppf x = fprintf ppf "%s" x

(** extracts the ppf from the given accumulator and outputs a newline *)
let ppf_newline acc = fprintf (ppf acc) "@\n"

(* pretty prints a definition name, if it should be unfolded *)
let pp_def_name acc0 fmt s =
  match undef acc0 with
  | true ->
    CCFormat.fprintf fmt "%s == " s
  | false ->
    CCFormat.fprintf fmt "%s" s

(** checks if a user defined operator is defined in a standard module
    (TLAPS, Naturals etc.) *)
let is_standard_location location =
  match location.filename with
  | "--TLA+ BUILTINS--"
  | "TLAPS"
  | "TLC"
  | "Naturals" -> true
  | _ -> false

class formatter =
  object(self)
    inherit [fc] visitor as super

    (* parts of expressions *)
    method location acc { column; line; filename } : 'a =
    (*
    fprintf (ppf acc) "(%s:l%d-%d c%d-%d)"
            filename line.rbegin line.rend
            column.rbegin column.rend;
     *)
      acc
    method level acc l : 'a =
    (*
    let lstr = match l with
    | None -> "(no level)"
    | Some ConstantLevel -> "(Constant)"
    | Some VariableLevel -> "(Variable)"
    | Some ActionLevel -> "(Action)"
    | Some TemporalLevel -> "(Temporal)"
    in
    fprintf (ppf acc) "%s" lstr;
     *)
      acc

    (* non-recursive expressions *)
    method decimal acc { location; level; mantissa; exponent;  } =
      let value =
        (float_of_int mantissa) /. ( 10.0 ** (float_of_int exponent)) in
      fprintf (ppf acc) "%s" (string_of_float value);
      acc

    method numeral acc {location; level; value } =
      fprintf (ppf acc) "%s" (string_of_int value);
      acc

    method strng acc {location; level; value} =
      fprintf (ppf acc) "\"%s\"" value;
      acc

    method op_arg acc {location; level; argument } =
      (* fprintf (ppf acc) "%s" name;
         acc *)
      self#operator acc argument

    (* recursive expressions *)
    method at acc0 {location; level; except; except_component} =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let acc3 = self#op_appl_or_binder acc2 except in
      let acc = self#op_appl_or_binder acc3 except_component in
      (* todo make this better or manually remove the @ operators? *)
      fprintf (ppf acc) "@@" ;
      acc

    method op_appl acc0 {location; level; operator; operands} =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      match match_fixity_op (tdb acc2) operator with
      | BinaryInfix ->
        (* infix binary operators *)
        fprintf (ppf acc2) "(";
        let left, right = match operands with
          | [l;r] -> l,r
          | _ -> failwith "Binary operator does not have 2 arguments!"
        in
        let acc3 = self#expr_or_op_arg acc2 left in
        fprintf (ppf acc3) " ";
        let acc4 = self#operator acc3 operator in
        fprintf (ppf acc4) " ";
        let acc5 = self#expr_or_op_arg acc4 right in
        fprintf (ppf acc5) ")";
        acc5
      | Special Builtin.IF_THEN_ELSE ->
        fprintf (ppf acc2) "(";
        let op1, op2, op3 = match operands with
          | [o1;o2;o3] -> o1,o2,o3
          | _ -> failwith "if-then-else operator does not have 3 arguments!"
        in
        fprintf (ppf acc2) "(IF ";
        let acc3 = self#expr_or_op_arg acc2 op1 in
        fprintf (ppf acc3) " THEN ";
        let acc4 = self#expr_or_op_arg acc3 op2 in
        fprintf (ppf acc4) " ELSE ";
        let acc5 = self#expr_or_op_arg acc4 op3 in
        fprintf (ppf acc5) ")";
        acc5
      | Special Builtin.FUN_APP ->
        (* TODO: not sure if the args need to be wrapped in prenthesis sometimes *)
        let f, args = match operands with
          | x::y::xs -> x, y::xs
          | _ -> failwith "Function application needs at least 2 arguments!"
        in
        let acc3 = self#expr_or_op_arg acc2 f in
        fprintf (ppf acc3) "[";
        let acc4 = ppf_fold_with self#expr_or_op_arg acc3 args in
        fprintf (ppf acc4) "]";
        acc4
      | Special Builtin.SET_ENUM ->
        fprintf (ppf acc2) "{";
        (* TODO: not sure if the args need to be wrapped in prenthesis sometimes *)
        let acc3 = ppf_fold_with self#expr_or_op_arg acc2 operands in
        fprintf (ppf acc3) "}";
        acc3
      | Special Builtin.TUPLE ->
        fprintf (ppf acc2) "<<";
        (* TODO: not sure if the args need to be wrapped in prenthesis sometimes *)
        let acc3 = ppf_fold_with self#expr_or_op_arg acc2 operands in
        fprintf (ppf acc3) ">>";
        acc3
      | Special _
      | UnaryPrefix|UnaryPostfix
      | Standard ->
        (* other operators *)
        let acc3 = self#operator acc2 operator in
        let oparens, cparens =
          if (operands <> []) then ("(",")") else ("","") in
        fprintf (ppf acc3) "%s" oparens;
        let acc4 = ppf_fold_with self#expr_or_op_arg acc3 operands in
        fprintf (ppf acc4) "%s" cparens;
        acc4

    method lambda acc0 {level; arity; body; params} =
      let acc1 = self#level acc0 level in
      fprintf (ppf acc1) "LAMBDA ";
      let acc2 = ppf_fold_with
          (fun x (fp,_) -> self#formal_param x fp) acc1 params in
      fprintf (ppf acc1) " : (";
      let acc3 = self#expr acc2 body in
      fprintf (ppf acc1) ")";
      acc3

    method binder acc0 {location; level; operator; operand; bound_symbols} =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let acc3 = self#operator acc2 operator in
      fprintf (ppf acc3) " ";
      let acc4 = ppf_fold_with self#bound_symbol acc3 bound_symbols in
      fprintf (ppf acc4) " : ";
      let oparens, cparens = "(",")" in
      fprintf (ppf acc4) "%s" oparens;
      let acc5 = self#expr_or_op_arg acc3 operand in
      fprintf (ppf acc5) "%s" cparens;
      acc4


    method bounded_bound_symbol acc { params; tuple; domain; } =
      match params with
      | [] ->
        failwith "Trying to process empty tuple of bound symbols with domain!"
      | [param] ->
        if tuple then fprintf (ppf acc) "<<";
        let acc1 = self#formal_param acc param in
        if tuple then fprintf (ppf acc1) ">> ";
        fprintf (ppf acc1) " \\in ";
        let acc2 = self#expr acc domain in
        acc2
      | _ ->
        fprintf (ppf acc) "<<";
        let acc1 = ppf_fold_with self#formal_param acc params in
        fprintf (ppf acc1) ">> \\in ";
        let acc2 = self#expr acc domain in
        acc2

    method unbounded_bound_symbol acc { param; tuple } =
      if tuple then fprintf (ppf acc) "<<";
      let acc1 = self#formal_param acc param in
      if tuple then fprintf (ppf acc1) ">> ";
      acc1

    method formal_param acc0 fp =
      let { location; level; name; arity; } : formal_param_ =
        Deref.formal_param (tdb acc0) fp in
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let acc3 = self#name acc2 name in
      fprintf (ppf acc3) "%s" name;
      (* arity skipped *)
      acc3

    method mule_entry acc me =
      (*      pp_open_vbox (ppf acc) 0; *)
      let acc0 = super#mule_entry (nest_module acc) me in
      (* pp_close_box (ppf acc0); *)
      acc0

    method mule acc0 = function
      | MOD_ref i ->
        let db = tdb acc0 in
        let inst = Deref.mule db (MOD_ref i) in
        self#mule_ acc0 inst

    method mule_ acc0 {name; location; module_entries } =
        match undef acc0 with
        | false -> (* don't expand module name *)
          fprintf (ppf acc0) "%s" name;
          acc0
        | true -> (* expand module name *)
          let acc0a = nest_module acc0 in
          pp_open_vbox (ppf acc0a) 0;
          fprintf (ppf acc0a) "==== MODULE %s ====@\n" name;
          ppf_newline acc0a;
          (*
          let print_block acc list_string sep handler list =  match list with
          | [] ->
             acc0;
          | _ ->
             fprintf (ppf acc0a) "%s " list_string;
             let racc = ppf_fold_with ~str:sep handler acc list in
             fprintf (ppf racc) "@,";
             racc
          in
           *)
          let acc = ppf_fold_with ~str:empty_formatter
              self#mule_entry
              acc0a module_entries in
          pp_close_box (ppf acc) ();
          fprintf (ppf acc) "@\n------------@\n";
          acc


    method op_decl acc0 opdec =
      let instance = Deref.op_decl (tdb acc0) opdec in
      self#op_decl_ acc0 instance

    method op_decl_ acc0 { location ; level ; name ; arity ; kind ; } =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      (* let acc3 = self#name acc2 name in *)
      let acc3 = match nesting acc0 with
        | Module ->
          (* terminal node *)
          let declaration_string = match kind with
            | ConstantDecl
            | NewConstant
              -> "CONSTANT"
            | VariableDecl
            | NewVariable
              -> "VARIABLE"
            | _ ->
              let msg =
                CCFormat.sprintf
                  "Global declaration %s can only be CONSTANT or VARIABLE."
                  (Commons.format_op_decl_kind kind)
              in
              failwith msg
          in
          fprintf (ppf acc2) "%s %s" declaration_string name ;
          ppf_newline acc2;
          acc2
        | ProofStep _
        | By
        | Expression ->
          (* the kind is only relevant in the new_symb rule *)
          (* terminal node *)
          fprintf (ppf acc2) "%s" name ;
          acc2
      in acc3

    method op_def acc = function
      | O_module_instance x ->
        self#module_instance acc x
      | O_builtin_op x      ->
        self#builtin_op acc x
      | O_thm_def x ->
        self#theorem_def acc x
      | O_assume_def x ->
        self#assume_def acc x
      | O_user_defined_op x ->
        self#user_defined_op acc x

    method assume_def acc0 asm =
      let instance = Deref.assume_def (tdb acc0) asm in
      self#assume_def_ acc0 instance

    method assume_def_ acc0 {id; location; level; name; body} =
      CCFormat.fprintf (ppf acc0) "%a" (pp_def_name acc0) name;
      (* self#expr acc0 body *)
      acc0

    method theorem_def acc0 thm =
      let instance = Deref.theorem_def (tdb acc0) thm in
      self#theorem_def_ acc0 instance

    method theorem_def_ acc0 {id; location; level; name; body} =
      CCFormat.fprintf (ppf acc0) "%a" (pp_def_name acc0) name;
      (* self#node acc0 body *)
      acc0

    method theorem acc0 thm =
      let instance = Deref.theorem (tdb acc0) thm in
      self#theorem_ acc0 instance

    method theorem_ acc0 { id; location; level; definition; statement; proof; } =
      match undef acc0, is_standard_location location with
      | true, true ->
        (* skip standard theorems TODO: check if we don't skip too much *)
        acc0
      | true, _ ->
        let thmstr = match nesting acc0 with
          | Module -> "THEOREM "
          | _ -> ""
        in
        pp_open_vbox (ppf acc0) 2;
        fprintf (ppf acc0) "%s" thmstr;
        let acc1 = match definition with
          | Some d ->
            self#theorem_def acc0 d
          | None ->
            acc0
        in
        let acc2 = nest_expr acc1 in
        let acc3 = self#statement acc2 statement in
        ppf_newline acc3;
        let acc3a = match nesting acc3 with
          | ProofStep i -> nest_proof acc3 (i+1)
          | _ -> nest_proof acc3 1
        in
        let acc4 = self#proof acc3a proof  in
        let acc4a = reset_nesting acc4 acc0 in
        pp_close_box (ppf acc0) ();
        ppf_newline acc4a;
        acc4a
      | false, _ ->
        failwith "Implementation error: theorems are only on the module level";

    (*TODO: check *)
    method statement acc0 = function
      | ST_FORMULA f ->
        self#node acc0 f
      | ST_SUFFICES f ->
        fprintf (ppf acc0) "SUFFICES ";
        self#node acc0 f
      | ST_CASE f ->
        fprintf (ppf acc0) "CASE ";
        self#expr acc0 f
      | ST_PICK {variables; formula } ->
        fprintf (ppf acc0) "PICK ";
        let acc1 = ppf_fold_with self#bound_symbol acc0 variables in
        fprintf (ppf acc1) " ";
        let acc2 = self#expr acc1 formula in
        acc2
      | ST_HAVE f ->
        fprintf (ppf acc0) "HAVE ";
        self#expr acc0 f
      | ST_TAKE bound_symbols ->
        let pp_bs =
          fprintf (ppf acc0) "TAKE \\A ";
          CCFormat.list ~sep:(CCFormat.return ", \\A ")
            (fun fmt bs ->
               ignore (self#bound_symbol acc0 bs)
            )
        in CCFormat.fprintf (ppf acc0) "%a" pp_bs bound_symbols;
        acc0
      | ST_WITNESS f ->
        fprintf (ppf acc0) "WITNESS ";
        self#expr acc0 f
      | ST_QED ->
        fprintf (ppf acc0) "QED ";
        acc0

    method assume acc0 x =
        self#assume_ acc0 (Deref.assume (tdb acc0) x)

    method assume_ acc0 {location; level; expr; } =
        let acc1 = self#location acc0 location in
        let acc2 = self#level acc1 level in
        fprintf (ppf acc2) "ASSUME " ;
        let acc3 = acc2 |> nest_expr |> disable_expand in
        let acc4 = self#expr acc3 expr in
        let acc = reset_nesting acc4 acc2
                  |> fun x -> reset_expand x acc2 in
        ppf_newline acc;
        acc

    method proof acc0 = function
      | P_omitted location ->
        fprintf (ppf acc0) " OMITTED";
        ppf_newline acc0;
        acc0
      | P_obvious location ->
        fprintf (ppf acc0) " OBVIOUS";
        ppf_newline acc0;
        acc0
      | P_by { location; level; facts; defs; only }  ->
        let acc1 = self#location acc0 location in
        let acc2 = self#level acc1 level in
        let by_only = if only then "ONLY " else "" in
        fprintf (ppf acc2) " BY %s" by_only;
        let acc3 = nest_by (disable_expand acc2) in
        let acc4 = ppf_fold_with
            self#expr_or_module_or_module_instance acc3 facts in
        let bydef = match facts, defs with
          | _, [] ->  ""
          | [],_ -> "DEF "
          | _ -> " DEF "
        in
        fprintf (ppf acc3) " %s" bydef;
        (* this loops because of self-reference to the containing theorem *)
        let acc5 = ppf_fold_with self#defined_expr acc4 defs in
        let acc = reset_nesting (reset_expand acc5 acc0) acc0 in
        ppf_newline acc;
        acc
      | P_steps { location; level; steps; } ->
        (* disable operator expansion, increase the proof nesting level *)
        let acc1 = inc_ndepth (disable_expand acc0) in
        let acc2 = ppf_fold_with ~str:empty_formatter self#step acc1 steps in
        ppf_newline acc2;
        (* reset expansion state and nesting level *)
        let acc = reset_ndepth (reset_expand acc2 acc0) acc0 in
        ppf_newline acc;
        acc
      | P_noproof ->
        ppf_newline acc0;
        acc0

    method step acc0 = function
      | S_def_step x -> self#def_step acc0 x
      | S_use_or_hide x -> self#use_or_hide acc0 x
      | S_instance i -> self#instance acc0 i
      | S_theorem t ->
        (* dereference theorem *)
        let thm = Deref.theorem (tdb acc0) t  in
        let stepname = match thm.definition with
          | Some tdr ->
            let td = Deref.theorem_def (tdb acc0) tdr in
            td.name
          | None ->
            (* failwith "A theorem as proofstep needs a name!" *)
            "<" ^ (string_of_int (ndepth acc0)) ^ ">."
        in
        fprintf (ppf acc0) "%s " stepname;
        let acc1 = enable_expand acc0 in
        let acc2 = self#theorem acc1 t in
        let acc = reset_expand acc2 acc0 in
        (*           ppf_newline acc; *)
        acc


    method use_or_hide acc0 {  location; level; facts; defs; only; hide } =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let uoh = if hide then " HIDE " else " USE " in
      ( match nesting acc2 with
        | ProofStep n ->
          fprintf (ppf acc2) "<%d> %s" n uoh;
        | Module ->
          fprintf (ppf acc2) "%s" uoh;
        | _ ->
          failwith "Implementation error: definition step outside of a proof!"
      );
      let acc3 = ppf_fold_with
          self#expr_or_module_or_module_instance acc2 facts in
      let bydef = if (defs <> []) then " DEF " else "" in
      fprintf (ppf acc3) "%s"  bydef;
      let acc = ppf_fold_with
          self#defined_expr acc3 defs in
      ppf_newline acc;
      acc

    method instance acc0 {location; level; name; module_name; substs; params; } =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let pp_name fmt = function
        | Some name ->
          fprintf (ppf acc2) "%s == " name;
          ()
        | None ->
          ()
      in
      fprintf (ppf acc2) "%aINSTANCE %s " pp_name name module_name;
      if (substs <> []) then
        fprintf (ppf acc2) "WITH ";
      let acc4 = nest_expr acc2 in
      let acc5 = List.fold_left self#instantiation acc4 substs in
      let acc = List.fold_left self#formal_param acc5 params in
      ppf_newline acc;
      acc

    method instantiation acc0 { op; expr; next } =
      let acc1 = self#op_decl acc0 op in
      fprintf (ppf acc1) " <- ";
      (* TODO: print the proper assignment based on if we are in- or outside of
         enabled *)
      let acc = self#expr_or_op_arg acc1 expr in
      acc

    method fp_assignment acc0 { param; expr } =
      let acc1 = self#formal_param acc0 param in
      fprintf (ppf acc1) " <- ";
      let acc = self#expr_or_op_arg acc1 expr in
      acc

    method assume_prove acc0 { location; level; new_symbols; assumes;
                               prove; suffices; boxed; } =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let s_suffices, s_prove = match (new_symbols, assumes) with
        | ( [], []) -> "", ""  (* empty antecedent *)
        | ( _,  _) ->  "ASSUME ", " PROVE "
      in
      fprintf (ppf acc2) "%s" s_suffices;
      let acc3 = ppf_fold_with
          self#new_symb acc2 new_symbols in
      let sep = if (new_symbols <> []) then ", " else "" in
      fprintf (ppf acc3) "%s" sep;
      let acc4 = ppf_fold_with
          self#node acc3 assumes in
      fprintf (ppf acc2) "%s" s_prove;
      let acc = self#expr acc4 prove in
      (* ppf_newline acc; *)
      acc

    (*TODO: new_decl not used *)
    method new_symb acc0 { location; level; op_decl; set } =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let od = Deref.op_decl (tdb acc0) op_decl in
      let new_decl = match od.kind with
        | NewConstant -> "" (* default is constant "CONSTANT " *)
        | NewVariable -> "VARIABLE "
        | NewState -> "STATE "
        | NewAction -> "ACTION "
        | NewTemporal -> "TEMPORAL "
        | _ -> failwith "declared new symbol with a non-new kind."
      in
      fprintf (ppf acc2) "NEW %s" new_decl;
      let acc3 = self#op_decl acc2 op_decl in
      let acc = match set with
        | None -> acc3
        | Some e ->
          fprintf (ppf acc3) " \\in ";
          self#expr acc3 e
      in acc

    (* TODO *)
    method let_in acc0 {location; level; body; op_defs } =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let acc3 = self#expr acc2 body in
      let acc = List.fold_left self#op_def_or_theorem_or_assume acc3 op_defs in
      acc

    (* TODO: this is not legal tla *)
    method subst_in acc0 ({ location; level; substs; body } : subst_in) =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      fprintf (ppf acc2) "$subst(";
      let acc3 = List.fold_left self#instantiation acc2 substs in
      fprintf (ppf acc3) ")(";
      let acc = self#expr acc3 body in
      fprintf (ppf acc3) ")";
      acc

    method fp_subst_in acc0 ({ location; level; substs; body } : fp_subst_in) =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      fprintf (ppf acc2) "$fp_subst(";
      let acc3 = List.fold_left self#fp_assignment acc2 substs in
      fprintf (ppf acc3) ")(";
      let acc = self#expr acc3 body in
      fprintf (ppf acc3) ")";
      acc

    (* TODO *)
    method label acc0 ({location; level; name; arity; body; params } : label) =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let acc3 = self#name acc2 name in
      (* skip arity *)
      fprintf (ppf acc3) "(label)";
      let acc4 = self#node acc3 body in
      let acc = List.fold_left self#formal_param acc4 params in
      acc

    (* TODO this is not legal tla *)
    method ap_subst_in acc0 ({ location; level; substs; body } : ap_subst_in) =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      fprintf (ppf acc2) "apsubstin(";
      let acc3 = List.fold_left self#instantiation acc2 substs in
      fprintf (ppf acc3) ")(";
      let acc = self#node acc3 body in
      fprintf (ppf acc) ")";
      acc

    method def_step acc0 { location; level; defs } =
      let acc1 = self#location acc0 location in
      let acc2 = self#level acc1 level in
      let pnesting = match nesting acc2 with
        | ProofStep n -> n
        | _ -> failwith "Implementation error: definition step outside of a proof!"
      in
      fprintf (ppf acc2) "<%d> DEFINE " pnesting;
      let acc3 = enable_expand acc2 in
      let acc4 = List.fold_left self#op_def acc3 defs in
      ppf_newline acc4;
      let acc = reset_expand acc4 acc0 in
      acc

    method module_instance acc0 mi =
      let instance = Deref.module_instance (tdb acc0) mi in
      self#module_instance_ acc0 instance

    (* TODO *)
    method module_instance_ acc0 {location; level; name} =
        fprintf (ppf acc0) "(module instance %s )" name;
        let acc = self#name acc0 name in
        acc

    method builtin_op acc0 b =
      let instance = Deref.builtin_op (tdb acc0) b in
      self#builtin_op_ acc0 instance

    method builtin_op_ acc0 { level; name; arity; params } =
        let acc1 = self#level acc0 level in
        let acc2 = self#name acc1 name in
        fprintf (ppf acc0) "%s" (self#translate_builtin_name name);
        acc2

    method user_defined_op acc0 op =
      let { location; level ; name ; arity ;
            body ; params ; recursive } =
        Deref.user_defined_op (tdb acc0) op in
        match nesting acc0, undef acc0, is_standard_location location with
        | Module, _, true ->
          (* skip standard libraries *)
          (* fprintf (ppf acc0) "(* ignoring def of builtin %s *)" name; *)
          (* ppf_newline acc0; *)
          acc0
        | Module, _, _ ->
          fprintf (ppf acc0) "%s" name;
          if (params <> []) then fprintf (ppf acc0) "(";
          let fparams = List.map fst params in
          if (params <> []) then fprintf (ppf acc0) ")";
          let acc0a = ppf_fold_with self#formal_param acc0 fparams in
          fprintf (ppf acc0) " == ";
          let acc1 = nest_expr acc0a in
          let acc2 = self#expr acc1 body in
          let acc3 = reset_nesting acc2 acc0 in
          let acc4 = reset_expand acc3 acc0 in
          ppf_newline acc4;
          ppf_newline acc4;
          acc4
        | By, _, _
        | ProofStep _, _, _
        | Expression, _, _ ->
          fprintf (ppf acc0) "%s" name;
          acc0

    method name acc x = acc

    method reference acc x = acc


    method context acc { root_module; entries; modules } =
      let ms = List.filter (fun x ->
          let m = Deref.mule entries x in
          m.name = root_module
        ) modules in
      let acc1 = List.fold_left self#mule acc ms in
      acc1

    method translate_builtin_name = function
      (*    | "$AngleAct"  as x -> failwith ("Unknown operator " ^ x ^"!") *)
      | "$BoundedChoose" -> "CHOOSE"
      | "$BoundedExists" -> "\\E"
      | "$BoundedForall" -> "\\A"
      | "$Case" -> "CASE"
      | "$CartesianProd" -> "\times"
      | "$ConjList" -> "/\\"
      | "$DisjList" -> "\\/"
      | "$Except" -> "EXCEPT"
      (*    | "$FcnApply" as x -> failwith ("Unknown operator " ^ x ^"!") *)
      (*    | "$FcnConstructor"  as x -> failwith ("Unknown operator " ^ x ^"!") *)
      | "$IfThenElse" -> "IFTHENELSE"
      (*    | "$NonRecursiveFcnSpec"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$Pair"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$RcdConstructor"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$RcdSelect"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$RecursiveFcnSpec"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$Seq"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$SquareAct"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$SetEnumerate"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$SF"  as x -> failwith ("Unknown operator " ^ x ^"!")
            | "$SetOfAll" as x  -> failwith ("Unknown operator " ^ x ^"!")
            | "$SetOfRcds" as x  -> failwith ("Unknown operator " ^ x ^"!")
            | "$SetOfFcns" as x  -> failwith ("Unknown operator " ^ x ^"!")
            | "$SubsetOf" as x  -> failwith ("Unknown operator " ^ x ^"!")
            | "$Tuple" as x  -> failwith ("Unknown operator " ^ x ^"!") *)
      | "$TemporalExists" -> "\\EE"
      | "$TemporalForall" -> "\\AA"
      | "$UnboundedChoose" -> "CHOOSE"
      | "$UnboundedExists" -> "\\E"
      | "$UnboundedForall" -> "\\A"
      (*    | "$WF" as x  -> failwith ("Unknown operator " ^ x ^"!")
            | "$Nop" as x -> failwith ("Unknown operator " ^ x ^"!") *)
      (*    | "$Qed" -> "QED" *)
      (*    | "$Pfcase" -> "CASE" *)
      (*    | "$Have" -> "HAVE" *)
      (*    | "$Take" -> "TAKE" *)
      (*    | "$Pick" -> "PICK" *)
      (*    | "$Witness" -> "WITNESS" *)
      (*    | "$Suffices" -> "SUFFICES" *)
      (* manual additions *)
      | "\\land" -> "/\\"
      | "\\lor" -> "\\/"
      | x -> x (* catchall case *)
  end

let expr_formatter = new formatter

let mk_fmt (f : fc -> 'a -> fc) term_db fmt (expr : 'a) =
  let acc = (fmt, term_db, true, Expression, 0) in
  ignore (f acc expr)

let mk_printer (f : fc -> 'a -> fc) term_db channel (expr : 'a) =
  mk_fmt f term_db (formatter_of_out_channel channel) expr

let prnt_expr = mk_printer (expr_formatter#expr)

let prnt_assume_prove = mk_printer (expr_formatter#assume_prove)

let prnt_statement  = mk_printer (expr_formatter#statement)

let fmt_expr = mk_fmt (expr_formatter#expr)

let fmt_assume_prove = mk_fmt (expr_formatter#assume_prove)

let fmt_statement  = mk_fmt (expr_formatter#statement)

let fmt_op_decl  = mk_fmt (expr_formatter#op_decl)

let fmt_expr_or_op_arg  = mk_fmt (expr_formatter#expr_or_op_arg)

let fmt_formal_param  = mk_fmt (expr_formatter#formal_param)

let fmt_node =  mk_fmt (expr_formatter#node)

let fmt_bound_symbol =  mk_fmt (expr_formatter#bound_symbol)

let fmt_operator = mk_fmt (expr_formatter#operator)
