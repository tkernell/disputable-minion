# Disputable Minion

A contract that allows execution of arbitrary calls voted on by members of a Moloch DAO. Allows moloch members to dispute minion proposals using pre-defined list of arbitration services. 

## Disputable Minion Proposal Lifecycle
1. Propose Action
	- Submit proposal deposit fee 1x
2. Proposal goes to moloch contract
	- Sponser -\> Vote -\> Process
3. Process Action
	- New processAction() method on minion side starts dispute delay period clock
4. Challenge Action
	- Moloch `share` and `loot` holders can challenge proposal by depositing 2x proposal deposit fee
5. Dispute Action or Abstain
	- The proposal submitter can accept the challenge by depositing 1x deposit fee and choosing an arbitrator
6. Rule
	- Arbitrator commits its decision in a dispute
7. Execute Action
	- If proposal is not disputed, execute the action once the `disputeDelayDuration` has expired
8. Withdraw deposit
	- If proposal went to arbitration, the arbitration winner withdraws the remaining balance of proposal deposit. Otherwise, the submitter withdraws the deposit.