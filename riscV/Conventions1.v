(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*           Prashanth Mundkur, SRI International                      *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(*  The contributions by Prashanth Mundkur are reused and adapted      *)
(*  under the terms of a Contributor License Agreement between         *)
(*  SRI International and INRIA.                                       *)
(*                                                                     *)
(* *********************************************************************)

(** Function calling conventions and other conventions regarding the use of
    machine registers and stack slots. *)

Require Import Coqlib Decidableplus.
Require Import AST Machregs Locations.

(** * Classification of machine registers *)

(** Machine registers (type [mreg] in module [Locations]) are divided in
  the following groups:
- Callee-save registers, whose value is preserved across a function call.
- Caller-save registers that can be modified during a function call.

  We follow the RISC-V application binary interface (ABI) in our choice
  of callee- and caller-save registers.
*)

Definition is_callee_save (r: mreg) : bool :=
  match r with
  | R5 | R6 | R7 => false
  | R8 | R9 => true
  | R10 | R11 | R12 | R13 | R14 | R15 | R16 | R17 => false
  | R18 | R19 | R20 | R21 | R22 | R23 | R24 | R25 | R26 | R27 => true
  | R28 | R29 | R30 => false
  | F0 | F1 | F2 | F3 | F4 | F5 | F6 | F7 => false
  | F8 | F9 => true
  | F10 | F11 | F12 | F13 | F14 | F15 | F16 | F17 => false
  | F18 | F19 | F20 | F21 | F22 | F23 | F24 | F25 | F26 | F27 => true
  | F28 | F29 | F30 | F31 => false
  end.

Definition int_caller_save_regs :=
  R5  :: R6  :: R7 ::
  R10 :: R11 :: R12 :: R13 :: R14 :: R15 :: R16 :: R17 ::
  R28 :: R29 :: R30 ::
  nil.

Definition float_caller_save_regs :=
  F0  :: F1  :: F2  :: F3  :: F4  :: F5  :: F6  :: F7  ::
  F10 :: F11 :: F12 :: F13 :: F14 :: F15 :: F16 :: F17 ::
  F28 :: F29 :: F30 :: F31 ::
  nil.

Definition int_callee_save_regs :=
  R8  :: R9  ::
  R18 :: R19 :: R20 :: R21 :: R22 :: R23 :: R24 :: R25 :: R26 :: R27 ::
  nil.

Definition float_callee_save_regs :=
  F8  :: F9  ::
  F18 :: F19 :: F20 :: F21 :: F22 :: F23 :: F24 :: F25 :: F26 :: F27 ::
  nil.

Definition destroyed_at_call :=
  List.filter (fun r => negb (is_callee_save r)) all_mregs.

Definition dummy_int_reg   := R6.    (**r Used in [Coloring]. *)
Definition dummy_float_reg := F0 .   (**r Used in [Coloring]. *)

Definition callee_save_type := mreg_type.
  
Definition is_float_reg (r: mreg) :=
  match r with
        | R5  | R6  | R7  | R8  | R9  | R10 | R11
  | R12 | R13 | R14 | R15 | R16 | R17 | R18 | R19
  | R20 | R21 | R22 | R23 | R24 | R25 | R26 | R27
  | R28 | R29 | R30 => false

  | F0  | F1  | F2  | F3  | F4  | F5  | F6  | F7
  | F8  | F9  | F10 | F11 | F12 | F13 | F14 | F15
  | F16 | F17 | F18 | F19 | F20 | F21 | F22 | F23
  | F24 | F25 | F26 | F27 | F28 | F29 | F30 | F31 => true
  end.

(** * Function calling conventions *)

(** The functions in this section determine the locations (machine registers
  and stack slots) used to communicate arguments and results between the
  caller and the callee during function calls.  These locations are functions
  of the signature of the function and of the call instruction.
  Agreement between the caller and the callee on the locations to use
  is guaranteed by our dynamic semantics for Cminor and RTL, which demand
  that the signature of the call instruction is identical to that of the
  called function.

  Calling conventions are largely arbitrary: they must respect the properties
  proved in this section (such as no overlapping between the locations
  of function arguments), but this leaves much liberty in choosing actual
  locations.  To ensure binary interoperability of code generated by our
  compiler with libraries compiled by another compiler, we
  implement the standard RISC-V conventions.  *)

(** ** Location of function result *)

(** The result value of a function is passed back to the caller in
  registers [R10] or [F10] or [R10,R11], depending on the type of the
  returned value.  We treat a function without result as a function
  with one integer result. *)

Definition loc_result (s: signature) : rpair mreg :=
  match s.(sig_res) with
  | None => One R10
  | Some (Tint | Tany32) => One R10
  | Some (Tfloat | Tsingle | Tany64) => One F10
  | Some Tlong => if Archi.ptr64 then One R10 else Twolong R11 R10
  end.

(** The result registers have types compatible with that given in the signature. *)

Lemma loc_result_type:
  forall sig,
  subtype (proj_sig_res sig) (typ_rpair mreg_type (loc_result sig)) = true.
Proof.
  intros. unfold proj_sig_res, loc_result, mreg_type;
  destruct (sig_res sig) as [[]|]; auto; destruct Archi.ptr64; auto.
Qed.

(** The result locations are caller-save registers *)

Lemma loc_result_caller_save:
  forall (s: signature),
  forall_rpair (fun r => is_callee_save r = false) (loc_result s).
Proof.
  intros. unfold loc_result, is_callee_save;
  destruct (sig_res s) as [[]|]; simpl; auto; destruct Archi.ptr64; simpl; auto.
Qed.

(** If the result is in a pair of registers, those registers are distinct and have type [Tint] at least. *)

Lemma loc_result_pair:
  forall sg,
  match loc_result sg with
  | One _ => True
  | Twolong r1 r2 =>
       r1 <> r2 /\ sg.(sig_res) = Some Tlong
    /\ subtype Tint (mreg_type r1) = true /\ subtype Tint (mreg_type r2) = true 
    /\ Archi.ptr64 = false
  end.
Proof.
  intros.
  unfold loc_result; destruct (sig_res sg) as [[]|]; auto.
  unfold mreg_type; destruct Archi.ptr64; auto.
  split; auto. congruence.
Qed.

(** The location of the result depends only on the result part of the signature *)

Lemma loc_result_exten:
  forall s1 s2, s1.(sig_res) = s2.(sig_res) -> loc_result s1 = loc_result s2.
Proof.
  intros. unfold loc_result. rewrite H; auto.  
Qed.

(** ** Location of function arguments *)

(** The RISC-V ABI states the following convention for passing arguments
  to a function:

- Arguments are passed in registers when possible.

- Up to eight integer registers (ai: int_param_regs) and up to eight
  floating-point registers (fai: float_param_regs) are used for this
  purpose.

- If the arguments to a function are conceptualized as fields of a C
  struct, each with pointer alignment, the argument registers are a
  shadow of the first eight pointer-words of that struct. If argument
  i < 8 is a floating-point type, it is passed in floating-point
  register fa_i; otherwise, it is passed in integer register a_i.

- When primitive arguments twice the size of a pointer-word are passed
  on the stack, they are naturally aligned. When they are passed in the
  integer registers, they reside in an aligned even-odd register pair,
  with the even register holding the least-significant bits.

- Floating-point arguments to variadic functions (except those that
  are explicitly named in the parameter list) are passed in integer
  registers.

- The portion of the conceptual struct that is not passed in argument
  registers is passed on the stack. The stack pointer sp points to the
  first argument not passed in a register.

The bit about variadic functions doesn't quite fit CompCert's model.
We do our best by passing the FP arguments in registers, as usual,
and reserving the corresponding integer registers, so that fixup
code can be introduced in the Asmexpand pass.
*)

Definition int_param_regs :=
  R10 :: R11 :: R12 :: R13 :: R14 :: R15 :: R16 :: R17 :: nil.
Definition float_param_regs :=
  F10 :: F11 :: F12 :: F13 :: F14 :: F15 :: F16 :: F17 :: nil.

Definition one_arg (regs: list mreg) (rn: Z) (ofs: Z) (ty: typ)
                           (rec: Z -> Z -> list (rpair loc)) :=
  match list_nth_z regs rn with
  | Some r =>
      One(R r) :: rec (rn + 1) ofs
  | None   =>
      let ofs := align ofs (typealign ty) in
      One(S Outgoing ofs ty) :: rec rn (ofs + (if Archi.ptr64 then 2 else typesize ty))
  end.

Definition two_args (regs: list mreg) (rn: Z) (ofs: Z)
                    (rec: Z -> Z -> list (rpair loc)) :=
  let rn := align rn 2 in
  match list_nth_z regs rn, list_nth_z regs (rn + 1) with
  | Some r1, Some r2 =>
      Twolong (R r2) (R r1) :: rec (rn + 2) ofs
  | _, _ =>
      let ofs := align ofs 2 in
      Twolong (S Outgoing (ofs + 1) Tint) (S Outgoing ofs Tint) ::
      rec rn (ofs + 2)
  end.

Definition hybrid_arg (regs: list mreg) (rn: Z) (ofs: Z) (ty: typ)
                      (rec: Z -> Z -> list (rpair loc)) :=
  let rn := align rn 2 in
  match list_nth_z regs rn with
  | Some r =>
      One (R r) :: rec (rn + 2) ofs
  | None =>
      let ofs := align ofs 2 in
      One (S Outgoing ofs ty) :: rec rn (ofs + 2)
  end.

Fixpoint loc_arguments_rec (va: bool)
    (tyl: list typ) (r ofs: Z) {struct tyl} : list (rpair loc) :=
  match tyl with
  | nil => nil
  | (Tint | Tany32) as ty :: tys =>
      one_arg int_param_regs r ofs ty (loc_arguments_rec va tys)
  | Tsingle as ty :: tys =>
      one_arg float_param_regs r ofs ty (loc_arguments_rec va tys)
  | Tlong as ty :: tys =>
      if Archi.ptr64
      then one_arg int_param_regs r ofs ty (loc_arguments_rec va tys)
      else two_args int_param_regs r ofs  (loc_arguments_rec va tys)
  | (Tfloat | Tany64) as ty :: tys =>
      if va && negb Archi.ptr64
      then hybrid_arg float_param_regs r ofs ty (loc_arguments_rec va tys)
      else one_arg float_param_regs r ofs ty (loc_arguments_rec va tys)
  end.

(** [loc_arguments s] returns the list of locations where to store arguments
  when calling a function with signature [s].  *)

Definition loc_arguments (s: signature) : list (rpair loc) :=
  loc_arguments_rec s.(sig_cc).(cc_vararg) s.(sig_args) 0 0.

(** [size_arguments s] returns the number of [Outgoing] slots used
  to call a function with signature [s]. *)

Definition max_outgoing_1 (accu: Z) (l: loc) : Z :=
  match l with
  | S Outgoing ofs ty => Z.max accu (ofs + typesize ty)
  | _ => accu
  end.

Definition max_outgoing_2 (accu: Z) (rl: rpair loc) : Z :=
  match rl with
  | One l => max_outgoing_1 accu l
  | Twolong l1 l2 => max_outgoing_1 (max_outgoing_1 accu l1) l2
  end.

Definition size_arguments (s: signature) : Z :=
  List.fold_left max_outgoing_2 (loc_arguments s) 0.

(** Argument locations are either non-temporary registers or [Outgoing]
  stack slots at nonnegative offsets. *)

Definition loc_argument_acceptable (l: loc) : Prop :=
  match l with
  | R r => is_callee_save r = false
  | S Outgoing ofs ty => ofs >= 0 /\ (typealign ty | ofs)
  | _ => False
  end.

Lemma loc_arguments_rec_charact:
  forall va tyl rn ofs p,
  ofs >= 0 ->
  In p (loc_arguments_rec va tyl rn ofs) -> forall_rpair loc_argument_acceptable p.
Proof.
  set (OK := fun (l: list (rpair loc)) =>
             forall p, In p l -> forall_rpair loc_argument_acceptable p).
  set (OKF := fun (f: Z -> Z -> list (rpair loc)) =>
              forall rn ofs, ofs >= 0 -> OK (f rn ofs)).
  set (OKREGS := fun (l: list mreg) => forall r, In r l -> is_callee_save r = false).
  assert (AL: forall ofs ty, ofs >= 0 -> align ofs (typealign ty) >= 0).
  { intros. 
    assert (ofs <= align ofs (typealign ty)) by (apply align_le; apply typealign_pos).
    omega. }
  assert (SK: (if Archi.ptr64 then 2 else 1) > 0).
  { destruct Archi.ptr64; omega. }
  assert (SKK: forall ty, (if Archi.ptr64 then 2 else typesize ty) > 0).
  { intros. destruct Archi.ptr64. omega. apply typesize_pos.  }
  assert (A: forall regs rn ofs ty f,
             OKREGS regs -> OKF f -> ofs >= 0 -> OK (one_arg regs rn ofs ty f)).
  { intros until f; intros OR OF OO; red; unfold one_arg; intros.
    destruct (list_nth_z regs rn) as [r|] eqn:NTH; destruct H.
  - subst p; simpl. apply OR. eapply list_nth_z_in; eauto. 
  - eapply OF; eauto. 
  - subst p; simpl. auto using align_divides, typealign_pos.
  - eapply OF; [idtac|eauto].
    generalize (AL ofs ty OO) (SKK ty); omega.
  }
  assert (B: forall regs rn ofs f,
             OKREGS regs -> OKF f -> ofs >= 0 -> OK (two_args regs rn ofs f)).
  { intros until f; intros OR OF OO; unfold two_args.
    set (rn' := align rn 2).
    set (ofs' := align ofs 2).
    assert (OO': ofs' >= 0) by (apply (AL ofs Tlong); auto).
    assert (DFL: OK (Twolong (S Outgoing (ofs' + 1) Tint) (S Outgoing ofs' Tint)
                     :: f rn' (ofs' + 2))).
    { red; simpl; intros. destruct H.
    - subst p; simpl. 
      repeat split; auto using Z.divide_1_l. omega.
    - eapply OF; [idtac|eauto]. omega.
    }
    destruct (list_nth_z regs rn') as [r1|] eqn:NTH1;
    destruct (list_nth_z regs (rn' + 1)) as [r2|] eqn:NTH2;
    try apply DFL.
    red; simpl; intros; destruct H.
  - subst p; simpl. split; apply OR; eauto using list_nth_z_in.  
  - eapply OF; [idtac|eauto]. auto.
  }
  assert (C: forall regs rn ofs ty f,
             OKREGS regs -> OKF f -> ofs >= 0 -> typealign ty = 1 -> OK (hybrid_arg regs rn ofs ty f)).
  { intros until f; intros OR OF OO OTY; unfold hybrid_arg; red; intros.
    set (rn' := align rn 2) in *.
    destruct (list_nth_z regs rn') as [r|] eqn:NTH; destruct H.
  - subst p; simpl. apply OR. eapply list_nth_z_in; eauto. 
  - eapply OF; eauto. 
  - subst p; simpl. rewrite OTY. split. apply (AL ofs Tlong OO). apply Z.divide_1_l. 
  - eapply OF; [idtac|eauto]. generalize (AL ofs Tlong OO); simpl; omega.
  }
  assert (D: OKREGS int_param_regs).
  { red. decide_goal. }
  assert (E: OKREGS float_param_regs).
  { red. decide_goal. }

  cut (forall va tyl rn ofs, ofs >= 0 -> OK (loc_arguments_rec va tyl rn ofs)).
  unfold OK. eauto.
  induction tyl as [ | ty1 tyl]; intros until ofs; intros OO; simpl.
- red; simpl; tauto.
- destruct ty1.
+ (* int *) apply A; auto.
+ (* float *) 
  destruct (va && negb Archi.ptr64).
  apply C; auto.
  apply A; auto.
+ (* long *)
  destruct Archi.ptr64.
  apply A; auto.
  apply B; auto.
+ (* single *)
  apply A; auto.
+ (* any32 *)
  apply A; auto.
+ (* any64 *)
  destruct (va && negb Archi.ptr64).
  apply C; auto.
  apply A; auto.
Qed.

Lemma loc_arguments_acceptable:
  forall (s: signature) (p: rpair loc),
  In p (loc_arguments s) -> forall_rpair loc_argument_acceptable p.
Proof.
  unfold loc_arguments; intros. eapply loc_arguments_rec_charact; eauto. omega.
Qed.

(** The offsets of [Outgoing] arguments are below [size_arguments s]. *)

Remark fold_max_outgoing_above:
  forall l n, fold_left max_outgoing_2 l n >= n.
Proof.
  assert (A: forall n l, max_outgoing_1 n l >= n).
  { intros; unfold max_outgoing_1. destruct l as [_ | []]; xomega. }
  induction l; simpl; intros. 
  - omega.
  - eapply Zge_trans. eauto.
    destruct a; simpl. apply A. eapply Zge_trans; eauto.
Qed.

Lemma size_arguments_above:
  forall s, size_arguments s >= 0.
Proof.
  intros. apply fold_max_outgoing_above.
Qed.

Lemma loc_arguments_bounded:
  forall (s: signature) (ofs: Z) (ty: typ),
  In (S Outgoing ofs ty) (regs_of_rpairs (loc_arguments s)) ->
  ofs + typesize ty <= size_arguments s.
Proof.
  intros until ty.
  assert (A: forall n l, n <= max_outgoing_1 n l).
  { intros; unfold max_outgoing_1. destruct l as [_ | []]; xomega. }
  assert (B: forall p n,
             In (S Outgoing ofs ty) (regs_of_rpair p) ->
             ofs + typesize ty <= max_outgoing_2 n p).
  { intros. destruct p; simpl in H; intuition; subst; simpl.
  - xomega.
  - eapply Zle_trans. 2: apply A. xomega.
  - xomega. }
  assert (C: forall l n,
             In (S Outgoing ofs ty) (regs_of_rpairs l) ->
             ofs + typesize ty <= fold_left max_outgoing_2 l n).
  { induction l; simpl; intros.
  - contradiction.
  - rewrite in_app_iff in H. destruct H.
  + eapply Zle_trans. eapply B; eauto. apply Zge_le. apply fold_max_outgoing_above.
  + apply IHl; auto.
  }
  apply C. 
Qed.

Lemma loc_arguments_main:
  loc_arguments signature_main = nil.
Proof.
  reflexivity.
Qed.
