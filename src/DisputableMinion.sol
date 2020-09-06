pragma solidity 0.5.12;

import "./moloch/Moloch.sol";
// import "https://github.com/raid-guild/moloch-minion/blob/develop/contracts/moloch/Moloch.sol";

interface IArbitrator {
    /**
    * @dev Create a dispute over the Arbitrable sender with a number of possible rulings
    * @param _possibleRulings Number of possible rulings allowed for the dispute
    * @param _metadata Optional metadata that can be used to provide additional information on the dispute to be created
    * @return Dispute identification number
    */
    function createDispute(uint256 _possibleRulings, bytes calldata _metadata) external returns (uint256);

    /**
    * @dev Close the evidence period of a dispute
    * @param _disputeId Identification number of the dispute to close its evidence submitting period
    */
    function closeEvidencePeriod(uint256 _disputeId) external;

    /**
    * @dev Execute the Arbitrable associated to a dispute based on its final ruling
    * @param _disputeId Identification number of the dispute to be executed
    */
    function executeRuling(uint256 _disputeId) external;

    /**
    * @dev Tell the dispute fees information to create a dispute
    * @return recipient Address where the corresponding dispute fees must be transferred to
    * @return feeToken ERC20 token used for the fees
    * @return feeAmount Total amount of fees that must be allowed to the recipient
    */
    // function getDisputeFees() external view returns (address recipient, ERC20 feeToken, uint256 feeAmount);

    /**
    * @dev Tell the subscription fees information for a subscriber to be up-to-date
    * @param _subscriber Address of the account paying the subscription fees for
    * @return recipient Address where the corresponding subscriptions fees must be transferred to
    * @return feeToken ERC20 token used for the subscription fees
    * @return feeAmount Total amount of fees that must be allowed to the recipient
    */
    // function getSubscriptionFees(address _subscriber) external view returns (address recipient, ERC20 feeToken, uint256 feeAmount);
}

contract Minion {

    string public constant MINION_ACTION_DETAILS = '{"isMinion": true, "title":"MINION", "description":"';

    Moloch public moloch;
    address public molochApprovedToken;
    uint256 public disputeDelayDuration;
    enum RulingOptions {RefusedToArbitrate, ProposalInvalid, ProposalValid}
    uint constant numberOfRulingOptions = 2;
    mapping (uint256 => Action) public actions; // proposalId => Action
    mapping (uint256 => uint256) public disputes; // used for rule() method
    ADR[] public adrs;

    struct Action {
        uint256 value;
        address to;
        address proposer;
        bool executed;
        bytes data;
        bool disputed;
        bool disputable;
        bool processed;
        uint256 processingTime;
        uint256 arbitratorId;
        // bool[6] flags; // [sponsored, processed, didPass, cancelled, whitelist, guildkick]
    }
    struct ADR {
        address addr;
        string disputeMethod;   // createDispute() or relevant method for ADR chosen
        string details;         // Can be name, description, or something else
    }
    
    event ActionProposed(uint256 proposalId, address proposer);
    event ActionExecuted(uint256 proposalId, address executor);


    constructor(address _moloch, uint256 _disputeDelayDuration) public {
        moloch = Moloch(_moloch);
        molochApprovedToken = moloch.depositToken();
        disputeDelayDuration = _disputeDelayDuration;
    }

    // withdraw funds from the moloch
    function doWithdraw(address _token, uint256 _amount) public {
        moloch.withdrawBalance(_token, _amount);
    }

    function proposeAction(
        address _actionTo,
        uint256 _actionValue,
        bytes memory _actionData,
        string memory _description
    )
        public
        returns (uint256)
    {
        // No calls to zero address allows us to check that Minion submitted
        // the proposal without getting the proposal struct from the moloch
        require(_actionTo != address(0), "Minion::invalid _actionTo");

        string memory details = string(abi.encodePacked(MINION_ACTION_DETAILS, _description, '"}'));

        uint256 proposalId = moloch.submitProposal(
            address(this),
            0,
            0,
            0,
            molochApprovedToken,
            0,
            molochApprovedToken,
            details
        );

        Action memory action = Action({
            value: _actionValue,
            to: _actionTo,
            proposer: msg.sender,
            executed: false,
            data: _actionData,
            disputed: false,
            processed: false,
            processingTime: now,
            arbitratorId: 257,
            disputable: false
        });

        actions[proposalId] = action;

        emit ActionProposed(proposalId, msg.sender);
        return proposalId;
    }
    
    function processProposal(uint256 _proposalId) public {
        Action memory action = actions[_proposalId];
        bool[6] memory flags = moloch.getProposalFlags(_proposalId);
        
        // minion did not submit this proposal
        require(action.to != address(0), "Minion::invalid _proposalId");
        // can't call arbitrary functions on parent moloch
        require(action.to != address(moloch), "Minion::invalid target");
        require(!action.processed, "Minion::action processed");
        require(flags[2], "Minion::proposal not passed");
        
        actions[_proposalId].processed = true;
        actions[_proposalId].processingTime = now;
    }
    
    function disputeAction(uint256 _proposalId, uint256 _arbitratorId) public {
        Action memory action = actions[_proposalId];
        bool[6] memory flags = moloch.getProposalFlags(_proposalId);
        
        require(!action.disputed); // proposal cannot already be disputed
        require(action.processed); // proposal must have been processed on Minion side
        require(flags[2], "Minion::proposal not passed");
        require(!hasDisputeDelayDurationExpired(action.processingTime));
        
        ADR memory adr = adrs[_arbitratorId];
        (bool success, bytes memory retData) = adr.addr.call.value(0)(abi.encodeWithSignature(adr.disputeMethod, numberOfRulingOptions, ""));
        require(success, "Minion::call failure");
        uint256 disputeId = parse32BytesToUint256(retData);
        require(disputes[disputeId] == 0);
        actions[_proposalId].disputed = true;
        actions[_proposalId].arbitratorId = _arbitratorId;
        disputes[disputeId] = _proposalId;
    }
    
    function rule(uint256 _disputeID, uint256 _ruling) external { // Aragon
        require(_ruling <= numberOfRulingOptions);    // valid ruling value
        uint256 proposalId = disputes[_disputeID];    
        require(proposalId != 0);       // Reconsider?
        Action memory action = actions[proposalId];
        ADR memory adr = adrs[action.arbitratorId];
        require(adr.addr == msg.sender);              // only allow selected ADR contract
        require(action.disputed);                     // only callable if disputed
        action.disputed = _ruling <= 1;               // no longer disputed if ruling==2

    }
    
    function executeAction(uint256 _proposalId) public returns (bytes memory) {
        Action memory action = actions[_proposalId];
        bool[6] memory flags = moloch.getProposalFlags(_proposalId);

        // minion did not submit this proposal
        require(action.to != address(0), "Minion::invalid _proposalId");
        // can't call arbitrary functions on parent moloch
        require(action.to != address(moloch), "Minion::invalid target");
        require(!action.executed, "Minion::action executed");
        require(address(this).balance >= action.value, "Minion::insufficient eth");
        require(flags[2], "Minion::proposal not passed");

        // execute call
        actions[_proposalId].executed = true;
        (bool success, bytes memory retData) = action.to.call.value(action.value)(action.data);
        require(success, "Minion::call failure");
        emit ActionExecuted(_proposalId, msg.sender);
        return retData;
    }
    
    function hasDisputeDelayDurationExpired(uint256 startingTime) public view returns (bool) {
        return(now >= (startingTime + disputeDelayDuration)); // Change this to SafeMath-add
    }
    
    function parse32BytesToUint256(bytes memory data) pure public returns(uint256) {
        uint256 parsed;
        assembly {parsed := mload(add(data, 32))}
        return(parsed);
    }

    function() external payable { }
}
