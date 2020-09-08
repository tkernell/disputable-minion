# Disputable Minion

A contract that allows execution of arbitrary calls voted on by members of a Moloch DAO. Allows moloch members to dispute minion proposals using pre-defined list of arbitration services. 

## Disputable Minion Proposal Lifecycle
1. Propose Action
2. Proposal goes to moloch contract
	- Sponser -\> Vote -\> Process
3. Process Action
	- New processAction() method on minion side starts dispute delay period clock
4. Dispute Action
	- Moloch `share` and `loot` holders can raise a dispute and choose an arbitrator from the minion’s list of arbitrators
5. Rule
	- Arbitrator commits its decision in a dispute
6. Execute Action
	- If proposal is not disputed, execute the action once the `disputeDelayDuration` has expired