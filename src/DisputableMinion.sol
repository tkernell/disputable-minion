pragma solidity 0.5.12;

// import "./moloch/Moloch.sol";
import "https://github.com/raid-guild/moloch-minion/blob/develop/contracts/moloch/Moloch.sol";

contract IArbitrableAragon {
     bytes4 internal constant ARBITRABLE_INTERFACE_ID = bytes4(0x88f3ee69);
     function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == ARBITRABLE_INTERFACE_ID;// || _interfaceId == ERC165_INTERFACE_ID;
    }
}

contract DisputableMinion is IArbitrableAragon {
    using SafeMath for uint256;
    // --- Constants ---
    string public constant MINION_ACTION_DETAILS = '{"isMinion": true, "title":"MINION", "description":"';
    uint constant numberOfRulingOptions = 2; // RefusedToArbitrate, ProposalInvalid, ProposalValid

    // --- State and data structures ---
    Moloch public moloch;
    address public molochApprovedToken;
    uint256 public disputeDelayDuration;
    enum RulingOptions {RefusedToArbitrate, ProposalInvalid, ProposalValid} // Necessary?
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
        bytes4 disputeMethod;   // createDispute() or relevant method for ADR chosen
    }
    
    // --- Events ---
    event ActionProposed(uint256 proposalId, address proposer);
    event ActionProcessed(uint256 proposalId, address processor);
    event ActionDisputed(uint256 proposalId, address disputant, uint256 disputeId);
    event ActionRuled(uint256 proposalId, address arbitrator, uint256 ruling);
    event ActionExecuted(uint256 proposalId, address executor);

    // --- Constructor ---
    constructor(
        address _moloch, 
        uint256 _disputeDelayDuration, 
        address[] memory _ADR_addr, 
        bytes4[] memory _ADR_disputeMethod
    ) 
        public 
    {
        require(_ADR_addr.length == _ADR_disputeMethod.length);
        moloch = Moloch(_moloch);
        molochApprovedToken = moloch.depositToken();
        disputeDelayDuration = _disputeDelayDuration;
        
        uint8 count=0;
        while(count < _ADR_addr.length) {
            adrs.push(ADR(_ADR_addr[count], _ADR_disputeMethod[count]));
            count++;
        }
    }
    
    // --- Fallback function
    function() external payable { }

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
    
    function processAction(uint256 _proposalId) public {
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
        actions[_proposalId].disputable = true;
        
        emit ActionProcessed(_proposalId, msg.sender);
    }
    
    function disputeAction(uint256 _proposalId, uint256 _arbitratorId) public payable returns(uint256) {
        require(isMember(msg.sender), "Minion::not a member");  // only moloch share or loot holders
        Action memory action = actions[_proposalId];
        bool[6] memory flags = moloch.getProposalFlags(_proposalId);
        
        require(!action.disputed); // proposal cannot already be disputed
        require(action.processed); // proposal must have been processed on Minion side
        require(flags[2], "Minion::proposal not passed");
        require(!hasDisputeDelayDurationExpired(action.processingTime));
        
        ADR memory adr = adrs[_arbitratorId];
        (bool success, bytes memory retData) = adr.addr.call.value(msg.value)(abi.encodePacked(adr.disputeMethod, abi.encode(numberOfRulingOptions, "")));
        require(success, "Minion::call failure");
        uint256 disputeId = parse32BytesToUint256(retData);
        require(disputes[disputeId] == 0); // 
        actions[_proposalId].disputed = true;
        actions[_proposalId].arbitratorId = _arbitratorId;
        disputes[disputeId] = _proposalId;
        
        emit ActionDisputed(_proposalId, msg.sender, disputeId);
        return disputeId;
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
        
        emit ActionRuled(proposalId, msg.sender, _ruling);
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
        require(action.processed, "Minion::action not processed");
        require(!action.disputed, "Minion::action disputed");
        require(hasDisputeDelayDurationExpired(action.processingTime));
        

        // execute call
        actions[_proposalId].executed = true;
        (bool success, bytes memory retData) = action.to.call.value(action.value)(action.data);
        require(success, "Minion::call failure");
        emit ActionExecuted(_proposalId, msg.sender);
        return retData;
    }
    
    // --- View functions
    function hasDisputeDelayDurationExpired(uint256 startingTime) public view returns (bool) {
        return(now >= startingTime.add(disputeDelayDuration));
    }
    
    function isMember(address addr) public view returns(bool) {
        (, uint256 shares, uint256 loot, , , ) = moloch.members(addr);
        return (shares > 0 || loot > 0);
    } 
    
    // --- Pure functions
    function parse32BytesToUint256(bytes memory data) pure public returns(uint256) {
        uint256 parsed;
        assembly {parsed := mload(add(data, 32))}
        return(parsed);
    }

}