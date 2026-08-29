# predictor regression. one branch, 100 iterations, so the global history
# saturates quickly and gshare should converge on it.
#
# this program is the only one that catches the prediction skew bug: with the
# prediction registered a cycle behind the btb target, bp_taken redirected the
# pc for the wrong instruction, and since that instruction reaches EX with
# branch=0 nothing flushes and there is no recovery. r_type and b_type both
# passed while that was broken.
    addi x1, x0, 100
loop:
    addi x1, x1, -1
    bne  x1, x0, loop
    addi x2, x0, 1
    ebreak
