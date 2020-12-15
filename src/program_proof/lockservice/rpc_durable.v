From Perennial.Helpers Require Import NamedProps.
From Perennial.Helpers Require Import ModArith.
From Perennial.algebra Require Import auth_map.
From Perennial.program_proof Require Import proof_prelude.
From iris.algebra Require Import gmap lib.mono_nat.
From Perennial.program_proof.lockservice Require Import fmcounter_map rpc_base.

Section rpc_durable.
Context `{!heapG Σ}.
Context {A:Type} {R:Type}.
Context `{!rpcG Σ R}.

(** The per-request invariant now has 3 states.
initialized: Request created and "on its way" to the server.
done: The reply was computed as is waiting for the client to take notice.
dead: The client took out ownership of the reply. *)
Local Definition RPCRequest_durable_inv (γrpc:rpc_names) (γPost γPre:gname) (PreCond : A -> iProp Σ) (PostCond : A -> R -> iProp Σ) (req:RPCRequest) : iProp Σ :=
   "#Hlseq_bound" ∷ req.(Req_CID) fm[[γrpc.(cseq)]]> int.nat req.(Req_Seq)
    ∗ ( (* Initialized, but server has not started processing *)
      "Hreply" ∷ (req.(Req_CID), req.(Req_Seq)) [[γrpc.(rc)]]↦ None ∗
               ((∃ s, req.(Req_CID) fm[[γrpc.(lseq)]]↦{3/4} s) ∨ own γPre (Excl ()) ∗ PreCond req.(Req_Args) ) ∨ 
      (* Not doing full ownership of the fmcounter becuase we (probably) want to remember the value..k
        Doing 3/4 so we know that if we are given 3/4 ownership, then this disjunction can't be in the first case *)

      (* Server has finished processing; two sub-states for wether client has taken PostCond out *)
      req.(Req_CID) fm[[γrpc.(lseq)]]≥ int.nat req.(Req_Seq)
      ∗ (∃ (last_reply:R), (req.(Req_CID), req.(Req_Seq)) [[γrpc.(rc)]]↦ro Some last_reply
        ∗ (own γPost (Excl ()) ∨ PostCond req.(Req_Args) last_reply)
      )
    ).

Definition is_durable_RPCRequest (γrpc:rpc_names) (γPost γPre:gname) (PreCond : A -> iProp Σ) (PostCond : A -> R -> iProp Σ) (req:RPCRequest) : iProp Σ :=
  inv rpcRequestInvN (RPCRequest_durable_inv γrpc γPost γPre PreCond PostCond req).

Definition RPCServer_own_processing γrpc (req:@RPCRequest A) lastSeqM lastReplyM : iProp Σ :=
  req.(Req_CID) fm[[γrpc.(lseq)]]↦{1/4} int.nat (map_get lastSeqM req.(Req_CID)).1 ∗
  (req.(Req_CID) fm[[γrpc.(lseq)]]↦ int.nat (map_get lastSeqM req.(Req_CID)).1 -∗
  RPCServer_own γrpc lastSeqM lastReplyM).

(*
  (∃ s, req.(CID) fm[[γrpc.(lseq)]]↦{3 / 4} s) -∗
  RPCServer_own γrpc lastSeqM lastReplyM.
*)

(* TODO: own_processing is actually just a bigSep of ownerships; the -∗ is just a more convenient to use elsewhere*)
Global Instance RPCServer_own_processing_disc γrpc (req:@RPCRequest A) lastSeqM lastReplyM : Discretizable (RPCServer_own_processing γrpc req lastSeqM lastReplyM).
Admitted.

Lemma server_takes_request (req:@RPCRequest A) γrpc γPost γPre PreCond PostCond lastSeqM lastReplyM (old_seq:u64) :
  ((map_get lastSeqM req.(Req_CID)).1 = old_seq) →
  (int.Z req.(Req_Seq) > int.Z old_seq)%Z →
  is_durable_RPCRequest γrpc γPost γPre PreCond PostCond req -∗
  RPCServer_own γrpc lastSeqM lastReplyM
  ={⊤}=∗
  own γPre (Excl ()) ∗ ▷ PreCond req.(Req_Args) ∗
  RPCServer_own_processing γrpc req lastSeqM lastReplyM.
Proof.
  rewrite map_get_val.
  intros Hlseq Hrseq.
  iIntros "HreqInv Hsown"; iNamed "Hsown".
  iInv "HreqInv" as "[#>Hreqeq_lb Hcases]" "HMClose".
  iDestruct (big_sepS_elem_of_acc _ _ req.(Req_CID) with "Hlseq_own") as "[Hlseq_one Hlseq_own]";
    first by apply elem_of_fin_to_set.
  rewrite Hlseq.

  iDestruct "Hcases" as "[[>Hunproc Hpre]|Hproc]".
  {

    iDestruct "Hpre" as "[>Hbad|[>HγP Hpre]]".
    - iNamed "Hbad". iCombine "Hbad Hlseq_one" as "Hbad".
      iDestruct (own_valid with "Hbad") as %Hbad.
      apply singleton_valid in Hbad.
      apply mono_nat_auth_frac_op_valid in Hbad as [Hbad _].
      iExFalso; iPureIntro.
      by apply (Qp_not_add_le_r (3 / 4) 1).
    -
    (* TODO: want  to just do [Hlseq_one], but it applies the lemma in the wrong direction *)
    replace 1%Qp with (1/4 + 3/4)%Qp; last by apply Qp_quarter_three_quarter.
    iDestruct (fmcounter_map_sep _ (1/4) (3/4) with "Hlseq_one") as "[H1/4 H3/4]".
    replace (1/4 + 3/4)%Qp with 1%Qp; last by (symmetry; apply Qp_quarter_three_quarter).
    iMod ("HMClose" with "[Hunproc H3/4]") as "_".
    {
      iNext. iFrame "#".
      iLeft. iFrame. iLeft. eauto with iFrame.
    }
    iModIntro. iFrame.
    rewrite -Hlseq.
    iFrame.
    rewrite map_get_val.
    iFrame "#". iFrame. (* XXX: relies on framing order *)
  }
  {
    iAssert (▷ req.(Req_CID) fm[[γrpc.(lseq)]]≥ int.nat req.(Req_Seq))%I with "[Hproc]" as "#>Hlseq_lb".
    { iDestruct "Hproc" as "[Hlseq_lb _]"; done. }
    iDestruct (fmcounter_map_agree_lb with "Hlseq_one Hlseq_lb") as %Hlseq_lb_ineq.
    iExFalso; iPureIntro.
    replace (int.Z old_seq) with (Z.of_nat (int.nat old_seq)) in Hrseq; last by apply u64_Z_through_nat.
    replace (int.Z req.(Req_Seq)) with (Z.of_nat (int.nat req.(Req_Seq))) in Hlseq_lb_ineq; last by apply u64_Z_through_nat.
    lia.
  }
Qed.
  
(* Opposite of above *)
Lemma server_returns_request (req:@RPCRequest A) γrpc γPost γPre PreCond PostCond lastSeqM lastReplyM (old_seq:u64) :
  ((map_get lastSeqM req.(Req_CID)).1 = old_seq) →
  (int.Z req.(Req_Seq) > int.Z old_seq)%Z →
  is_durable_RPCRequest γrpc γPost γPre PreCond PostCond req -∗
  own γPre (Excl ()) -∗
  PreCond req.(Req_Args) -∗
  RPCServer_own_processing γrpc req lastSeqM lastReplyM
  ={⊤}=∗
  RPCServer_own γrpc lastSeqM lastReplyM.
Proof.
  rewrite map_get_val.
  intros Hlseq Hrseq.
  iIntros "HreqInv HγPre Hpre Hsrpc_proc".
  iInv "HreqInv" as "[#>Hreqeq_lb Hcases]" "HMClose".

  iDestruct "Hcases" as "[[>Hunproc Hpre2]|Hproc]".
  {
    iDestruct "Hpre2" as "[>H3/4|[>HγP Hpre2]]".
    - iNamed "H3/4".
      iDestruct "Hsrpc_proc" as "[H1/4 Hsrpc_lseq_rest]".
      iCombine "H1/4 H3/4" as "Hfmptsto".
      iDestruct (own_valid with "Hfmptsto") as %Hvalid.
      apply singleton_valid in Hvalid.
      apply mono_nat_auth_frac_op_valid in Hvalid as [_ <-].
      rewrite mono_nat_auth_frac_op.
      replace (1/4 + 3/4)%Qp with 1%Qp; last by (symmetry; apply Qp_quarter_three_quarter).
      iSpecialize ("Hsrpc_lseq_rest" with "Hfmptsto").
      iMod ("HMClose" with "[HγPre Hpre Hunproc]") as "_"; last by iModIntro.
      iNext. iFrame "#". iLeft. iFrame "#∗". iRight. iFrame.
    - by iDestruct (own_valid_2 with "HγP HγPre") as %Hbad.
  }
  {
    iAssert (▷ req.(Req_CID) fm[[γrpc.(lseq)]]≥ int.nat req.(Req_Seq))%I with "[Hproc]" as "#>Hlseq_lb".
    { iDestruct "Hproc" as "[Hlseq_lb _]"; done. }
    iDestruct "Hsrpc_proc" as "[H1/4 Hsrpc_lseq_rest]".
    iDestruct (fmcounter_map_agree_lb with "H1/4 Hlseq_lb") as %Hlseq_lb_ineq.
    iExFalso; iPureIntro.
    replace (int.Z old_seq) with (Z.of_nat (int.nat old_seq)) in Hrseq; last by apply u64_Z_through_nat.
    replace (int.Z req.(Req_Seq)) with (Z.of_nat (int.nat req.(Req_Seq))) in Hlseq_lb_ineq; last by apply u64_Z_through_nat.
    rewrite map_get_val in Hlseq_lb_ineq.
    rewrite Hlseq in Hlseq_lb_ineq.
    lia.
  }
Qed.

(* TODO: I think this SP will be annoying *)
Lemma server_executes_durable_request' (req:@RPCRequest A) reply γrpc γPost γPre PreCond PostCond lastSeqM lastReplyM (old_seq:u64) ctx ctx' SP:
  (* TODO: get rid of this requirement by putting γPre in the postcondition case *)
  ((map_get lastSeqM req.(Req_CID)).1 = old_seq) →
  (int.Z req.(Req_Seq) > int.Z old_seq)%Z →
  is_durable_RPCRequest γrpc γPost γPre PreCond PostCond req -∗
  is_RPCServer γrpc -∗
  RPCServer_own_processing γrpc req lastSeqM lastReplyM -∗
  own γPre (Excl()) -∗
  SP -∗
  (▷ SP -∗ ctx ==∗ PostCond req.(Req_Args) reply ∗ ctx') -∗
  ctx ={⊤}=∗
  (RPCReplyReceipt γrpc req reply ∗
  RPCServer_own γrpc (<[req.(Req_CID):=req.(Req_Seq)]> lastSeqM) (<[req.(Req_CID):=reply]> lastReplyM) ∗
  ctx').
Proof.
  rewrite map_get_val.
  intros Hlseq Hrseq.
  iIntros "#HreqInv #HsrvInv Hsrpc_proc HγPre HP Hfupd Hctx".
  iInv "HreqInv" as "[#>Hreqeq_lb Hcases]" "HMClose".
  iDestruct "Hcases" as "[[>Hrcptsto [>Hdurtok|[>HγPre2 _]]]|Hproc]".
  {
    iMod ("Hfupd" with "HP Hctx") as "[Hpost Hctx']".
    
    iInv replyTableInvN as ">HNinner" "HNClose".
    iNamed "HNinner".

    iDestruct (map_update _ _ (Some reply) with "Hrcctx Hrcptsto") as ">[Hrcctx Hrcptsto]".
    iDestruct (map_freeze with "Hrcctx Hrcptsto") as ">[Hrcctx #Hrcptsoro]".
    iDestruct (big_sepM_insert_2 _ _ (req.(Req_CID), req.(Req_Seq)) (Some reply) with "[Hreqeq_lb] Hcseq_lb") as "Hcseq_lb2"; eauto.
    iMod ("HNClose" with "[Hrcctx Hcseq_lb2]") as "_".
    {
      iNext. iExists _; iFrame "# ∗".
    }

    (* TODO: make this a lemma *)
    unfold RPCServer_own_processing.
    iDestruct "Hdurtok" as (s) "H3/4".
    iDestruct "Hsrpc_proc" as "[H1/4 Hsrpc_lseq_rest]".
    iCombine "H1/4 H3/4" as "Hfmptsto".
    iDestruct (own_valid with "Hfmptsto") as %Hvalid.
    apply singleton_valid in Hvalid.
    apply mono_nat_auth_frac_op_valid in Hvalid as [_ <-].
    rewrite mono_nat_auth_frac_op.
    replace (1/4 + 3/4)%Qp with 1%Qp; last by (symmetry; apply Qp_quarter_three_quarter).
    iDestruct ("Hsrpc_lseq_rest" with "Hfmptsto") as "Hsrpc".
    (* End of lemma-to-be *)

    iNamed "Hsrpc".
    iDestruct (big_sepS_elem_of_acc_impl req.(Req_CID) with "Hlseq_own") as "[Hlseq_one Hlseq_own]";
      first by apply elem_of_fin_to_set.
    rewrite Hlseq.
    iMod (fmcounter_map_update (int.nat req.(Req_Seq)) with "Hlseq_one") as "[Hlseq_one #Hlseq_new_lb]"; first by lia.
    (* set Ψ := λ x:u64, (fmcounter_map_own γrpc.(lseq) x 1%Qp (int.nat (default (U64 0) (<[req.(Req_CID) := req.(Req_Seq)]> lastSeqM !! cid))))%I. *)

    iMod ("HMClose" with "[Hpost]") as "_".
    { iNext. iFrame "#". iRight. iExists _; iFrame "#". by iRight. }
    iDestruct (big_sepM2_insert_2 _ lastSeqM lastReplyM req.(Req_CID) req.(Req_Seq) reply with "[Hreqeq_lb] Hrcagree") as "Hrcagree2"; eauto.
    iModIntro.
    iFrame "∗#".
    iApply ("Hlseq_own" with "[Hlseq_one]"); simpl.
    - rewrite lookup_insert. done.
    - iIntros "!#" (y [_ ?]). rewrite lookup_insert_ne //. eauto.
  }
  {
    by iDestruct (own_valid_2 with "HγPre2 HγPre") as %Hbad.
  }
  { (* TODO: make this a lemma; it gets used 3 times *)
    iAssert (▷ req.(Req_CID) fm[[γrpc.(lseq)]]≥ int.nat req.(Req_Seq))%I with "[Hproc]" as "#>Hlseq_lb".
    { iDestruct "Hproc" as "[Hlseq_lb _]"; done. }
    iDestruct "Hsrpc_proc" as "[H1/4 Hsrpc_lseq_rest]".
    iDestruct (fmcounter_map_agree_lb with "H1/4 Hlseq_lb") as %Hlseq_lb_ineq.
    iExFalso; iPureIntro.
    replace (int.Z old_seq) with (Z.of_nat (int.nat old_seq)) in Hrseq; last by apply u64_Z_through_nat.
    replace (int.Z req.(Req_Seq)) with (Z.of_nat (int.nat req.(Req_Seq))) in Hlseq_lb_ineq; last by apply u64_Z_through_nat.
    rewrite map_get_val in Hlseq_lb_ineq.
    rewrite Hlseq in Hlseq_lb_ineq.
    lia.
  }
Qed.

End rpc_durable.
