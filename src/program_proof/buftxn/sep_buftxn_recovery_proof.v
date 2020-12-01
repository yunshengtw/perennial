From Perennial.Helpers Require Import Map.
From iris.base_logic.lib Require Import mnat.
From Perennial.algebra Require Import auth_map liftable liftable2 log_heap async.

From Goose.github_com.mit_pdos.goose_nfsd Require Import buftxn.
From Perennial.program_logic Require Export ncinv.
From Perennial.program_proof Require Import buf.buf_proof addr.addr_proof txn.txn_proof.
From Perennial.program_proof Require buftxn.buftxn_proof.
From Perennial.program_proof Require Import buftxn.sep_buftxn_proof.
From Perennial.program_proof Require Import proof_prelude.
From Perennial.goose_lang.lib Require Import slice.typed_slice.
From Perennial.goose_lang.ffi Require Import disk_prelude.

Section goose_lang.
  Context `{!buftxnG Σ}.
  Context {N:namespace}.

  Implicit Types (l: loc) (γ: buftxn_names Σ) (γtxn: gname).
  Implicit Types (obj: object).

  Definition txn_init_ghost_state (logm_init: gmap addr object) γ : iProp Σ :=
    async_ctx γ.(buftxn_async_name) 1 {| latest := logm_init; pending := [] |}.

  (* NOTE(tej): we're combining the durable part with the resources into one
  definition here, unlike in lower layers (they should be fixed) *)
  Definition is_txn_durable γ dinit logm : iProp Σ :=
    is_txn_durable γ.(buftxn_txn_names) dinit ∗
    txn_resources γ.(buftxn_txn_names) logm ∗
    async_ctx γ.(buftxn_async_name) 1 logm.

  Definition txn_cfupd_cancel dinit k γ' : iProp Σ :=
    (<disc> (|C={⊤}_k=>
              ∃ logm', is_txn_durable γ' dinit logm' )).

  Definition crash_point γ logm crash_txn : iProp Σ :=
    (* TODO: wrap crash_txn in an agree, give out an exchanger ghost name for
    it *)
    async_ctx γ.(buftxn_async_name) 1 logm ∗
    ⌜length (possible logm) = crash_txn⌝.

  Definition token_exchanger (a:addr) crash_txn γ γ' : iProp Σ :=
    (∃ i, async.own_last_frag γ.(buftxn_async_name) a i) ∨
    (async.own_last_frag γ'.(buftxn_async_name) a crash_txn ∗ modify_token γ' a).

  (* TODO: exchange
  [ephemeral_txn_val crash_txn γ a v]
  for
  [ephemeral_txn_val crash_txn γ' a v]
   *)
  Definition ephemeral_txn_val_exchanger (a:addr) crash_txn γ γ' : iProp Σ :=
    ∃ v, ephemeral_txn_val γ.(buftxn_async_name) crash_txn a v ∗
         ephemeral_txn_val γ'.(buftxn_async_name) crash_txn a v.
  
  Definition addr_exchangers {A} txn γ γ' (m : gmap addr A) : iProp Σ :=
    ([∗ map] a↦_ ∈ m,
        token_exchanger a txn γ γ' ∗
        ephemeral_txn_val_exchanger a txn γ γ')%I.

  Definition sep_txn_exchanger γ γ' : iProp Σ :=
    ∃ logm crash_txn,
       "Hcrash_point" ∷ crash_point γ logm crash_txn ∗
       (* TODO need durable lb in γ *)
       "Hcrash_txn_durable" ∷ txn_durable γ' crash_txn ∗
       "Hexchanger" ∷ addr_exchangers crash_txn γ γ' (latest logm)
  .

  Lemma exchange_big_sepM_addrs γ γ' (m0 m1 : gmap addr object) crash_txn :
    dom (gset _) m0 ⊆ dom (gset _) m1 →
    "Hexchanger" ∷ addr_exchangers crash_txn γ γ' m1 -∗
    "Hold" ∷ [∗ map] k0↦x ∈ m0, ephemeral_txn_val γ.(buftxn_async_name) crash_txn k0 x -∗
    "Hexchanger" ∷ addr_exchangers crash_txn γ γ' m1 ∗
    "Hnew" ∷ [∗ map] k0↦x ∈ m0, ephemeral_txn_val γ'.(buftxn_async_name) crash_txn k0 x.
  Proof. Admitted.

  Definition txn_cinv γ γ' : iProp Σ :=
    □ |C={⊤}_0=> inv (N.@"txn") (sep_txn_exchanger γ γ').

  Lemma exchange_mapsto_commit γ γ' m0 m txn_id k :
  ("#Htxn_cinv" ∷ txn_cinv γ γ' ∗
  "Hold_vals" ∷ [∗ map] k↦x ∈ m0,
        ∃ i : nat, txn_durable γ i ∗
                   ephemeral_txn_val_range γ.(buftxn_async_name) i txn_id k x ∗
  "H" ∷ [∗ map] k↦x ∈ m, ephemeral_val_from γ.(buftxn_async_name) txn_id k x) -∗
  |C={⊤}_S k => ([∗ map] a↦v ∈ m0, durable_mapsto_own γ' a v) ∨
                ([∗ map] a↦v ∈ m, durable_mapsto_own γ' a v).
  Proof.
    iNamed 1.
    iMod ("Htxn_cinv") as "#Hinv"; first lia.
    iIntros "HC".
    iInv ("Hinv") as ">H" "Hclo".
    iNamed "H".
    iAssert (⌜m ⊆ dom _ logm.(latest)⌝)%I with "[-]" as "%Hdom".
    { admit. (* TODO: need to argue that having an ephemeral_val_from means you're in
           the domain of the latest thing in the async_ctx *) }

    destruct (decide (crash_txn < txn_id)).
    - (* We roll back, txn_id is not durable *)
      iAssert (([∗ map] k0↦x ∈ m0, ephemeral_txn_val γ.(buftxn_async_name) crash_txn k0 x)%I)
        with "[Hold_vals]" as "#Hold".
      {(* TODO: proving this weakening will require an exchanger connecting
         crash_txn to txn_durable γ *) admit. }
      admit.
    - (* We go forward, txn_id is durable *)
      admit.
  Admitted.


  Theorem wpc_MkTxn (d:loc) γ dinit logm k :
    {{{ is_txn_durable γ dinit logm }}}
      txn.MkTxn #d @ k; ⊤
    {{{ γ' (l: loc), RET #l;
        is_txn l γ.(buftxn_txn_names) dinit ∗
        is_txn_system N γ ∗
        txn_cfupd_cancel dinit k γ' ∗
        txn_cinv γ γ' }}}
    {{{ ∃ γ' logm', ⌜ γ'.(buftxn_txn_names).(txn_kinds) = γ.(buftxn_txn_names).(txn_kinds) ⌝ ∗
                   is_txn_durable γ' dinit logm' }}}.
  Proof.
  Abort.

End goose_lang.
