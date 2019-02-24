pragma solidity ^0.5.0;

contract SlotMachine {

  // ******************************
// START MACHINE DEFINITION

  // MACHINE SPECIFIC CONSTANTS AND VARIABLES
  uint8 constant numReel = 5;
  uint constant public maxMultiplier = 3252;

  // DEFINE THE PROBABILITIES FOR THE REEL SYMBOLS
  function makeMachine() internal {
    reels[0].probDenominator = 100;
    reels[0].probs = [12, 11, 11, 11, 11, 11, 11, 11, 11];
    reels[0].eventLabels = [0, 1, 2, 3, 4, 5, 6, 7, 8];
    reels[1].probDenominator = 100;
    reels[1].probs = [12, 11, 11, 11, 11, 11, 11, 11, 11];
    reels[1].eventLabels = [0, 1, 2, 3, 4, 5, 6, 7, 8];
    reels[2].probDenominator = 100;
    reels[2].probs = [12, 11, 11, 11, 11, 11, 11, 11, 11];
    reels[2].eventLabels = [0, 1, 2, 3, 4, 5, 6, 7, 8];
    reels[3].probDenominator = 100;
    reels[3].probs = [12, 11, 11, 11, 11, 11, 11, 11, 11];
    reels[3].eventLabels = [0, 1, 2, 3, 4, 5, 6, 7, 8];
    reels[4].probDenominator = 100;
    reels[4].probs = [12, 11, 11, 11, 11, 11, 11, 11, 11];
    reels[4].eventLabels = [0, 1, 2, 3, 4, 5, 6, 7, 8];
}

  // CALCULATE THE PAYOUT
  function paytable(uint[numReel] memory outcome, uint betAmount) internal returns (uint) {
    uint maxMatch = countMaxMatch(outcome);
    if (maxMatch == 4) {
      return betAmount * 81;
    }
    if (maxMatch == 5) {
      return betAmount * 3252;
    }
  }

// END MACHINE DEFINITION
// ******************************************

  // STRUCTURES
  struct Reel {
    uint probDenominator;
    uint[] probs;
    uint[] eventLabels;
  }

  struct Bet {
    address user;
    uint amount;
    uint block;
  }

  enum State { Active, Suspended }

  // PARAMETERS
  uint8 constant public maxHouseMembers = 20; // max number of investors/owners
  uint constant public minPercentageIncrease = 20; // min overage for kicking someone on funding
  uint constant public blockDelay = 0; // 0 for debugging, 3 for production
  uint public minDivisor = 1000000000;


  // VARIABLES
  address payable public owner;
  mapping(uint => Bet) public bets;
  mapping(uint => bool) public alreadyPlayed;
  uint public counter = 0;
  uint public nonceForRandom = 0;
  Reel[numReel] public reels;
  uint[numReel] thisOutcome;
  mapping(uint => uint[numReel]) public outcomes;
  mapping(uint => uint8) public symbolCounter;
  uint public award;

  uint[maxHouseMembers] public houseAccountsArray;
  bool[maxHouseMembers] public houseActiveArray;
  address payable [maxHouseMembers] public houseMemberArray;

  uint public houseAccountMin = 0;
  uint8 public houseAccountMinIndex = 0;

  State public state;

  // DEFINE EVENTS
  event BetPlaced(address user, uint amount, uint block, uint counter);
  event Awarded(uint id, uint award);
  event Spin(uint id, uint award);

  constructor () public payable {
    owner = msg.sender;
    makeMachine();
  }

  // DETERMINE THE OUTCOME SYMBOL FOR EACH REEL
  function sample(uint id) internal {
    uint thisRandom;
    uint thisHash;
    uint runningProbSum;
    uint i;

    for (i = 0; i < numReel; i++) {
      thisHash = uint(keccak256(abi.encodePacked(block.number, msg.sender, i)));
      thisRandom = thisHash % reels[i].probDenominator;
      // CONVERT RANDOM NUMBER TO EVENT
      runningProbSum = reels[i].probs[0] - 1;
      for (uint j = 0; j < reels[i].probs.length; j++){
        if (thisRandom <= runningProbSum) {
          thisOutcome[i] = reels[i].eventLabels[j];
          break;
        }
        else {
          runningProbSum += reels[i].probs[j + 1];
        }
      }
    }
    outcomes[id] = thisOutcome;
  }

  // DISTRIBUTE BETS AND AWARDS ACCORDING TO PERCENTAGE OWNERSHIP
  function distributeAmount(bool bet, uint amount) internal {
    uint balanceHouse= address(this).balance;
    for (uint i = 0; i < maxHouseMembers; i++) {
      if (houseActiveArray[i]) {

        // INCOMING BET
        if (bet) {
          houseAccountsArray[i] += (amount * houseAccountsArray[i]) / balanceHouse;
        }
        // OUTGOING PAYOUT
        else {
          houseAccountsArray[i] -= (amount * houseAccountsArray[i]) / balanceHouse;
        }
      }
    }
  }

  // REBALANCE AND FIX ACCUMULATED ROUNDING ERRORS
  function rebalance() public {
    uint accountsTotal = 0;
    for (uint8 i=0; i < maxHouseMembers; i++) {
      if (houseActiveArray[i]) {
        accountsTotal += houseAccountsArray[i];
      }
    }
    uint remainder = address(this).balance - accountsTotal;
    distributeAmount(true, remainder);
  }

  // PLACE A WAGER
  function wager () payable public {
    require( state == State.Active);
    require(msg.value % minDivisor == 0);
    bets[counter] = Bet(msg.sender, msg.value, block.number + blockDelay);
    distributeAmount(true, msg.value);
    emit BetPlaced(msg.sender, msg.value, block.number + blockDelay, counter);
    counter++;
  }

  // PLAY THE GAME
  function play (uint id) public {
      require( state == State.Active);
      Bet storage bet = bets[id];
      require(msg.sender == bet.user);
      require(block.number >= bet.block);
      require(block.number <= bet.block + 255);
      require(!alreadyPlayed[id]);

      sample(id);

      alreadyPlayed[id] = true;
      award = paytable(thisOutcome, bet.amount);

      if (award > 0) {
        if (award > address(this).balance) {
          award = address(this).balance;
        }
        distributeAmount(false, award);
        emit Awarded(id, award);
        msg.sender.transfer(award);
      }
      else {
        emit Awarded(id, award);
      }
  }

  function minHouseAccountGet() public {
    uint currentMin = address(this).balance;
    uint8 currentMinIndex = maxHouseMembers;

    for (uint8 i = 0; i < maxHouseMembers; i++) {
      if (!houseActiveArray[i]){
        houseAccountMin = 0;
        houseAccountMinIndex = i;
        return;
      }
      if (houseAccountsArray[i] < currentMin){
        currentMin = houseAccountsArray[i];
        currentMinIndex = i;
      }
    }
    houseAccountMin = currentMin;
    houseAccountMinIndex = currentMinIndex;
  }

  // TRY TO ADD A NEW MEMBER (OWNER/INVESTOR)
  function addMember(address payable addressToAdd, uint initialFund) internal {

    // CHECK IF ALREADY A MEMBER
    (bool isAlreadyMember, uint8 index) = indexFromAddressGet(addressToAdd);

    if (isAlreadyMember) {
      houseAccountsArray[index] += initialFund;
      houseActiveArray[index] = true;
      minHouseAccountGet();
      return;
    }
    else {
      if (initialFund > houseAccountMin + ((houseAccountMin * minPercentageIncrease)/100)) {
        houseAccountsArray[houseAccountMinIndex] = initialFund;
        houseActiveArray[houseAccountMinIndex] = true;
        houseMemberArray[houseAccountMinIndex] = addressToAdd;
        minHouseAccountGet();
        return;
      }
    }
  }

  // FUND THE CASINO
  function fund () public payable {
    require( state == State.Active);
    require(msg.value % minDivisor == 0);
    addMember(msg.sender, msg.value);
  }

  // REMOVE A MEMBER (OWNER/INVESTOR)
  function houseRemoveMember(address payable houseMember) internal {
    (bool memberFlag, uint8 index) = indexFromAddressGet(houseMember);

    if (memberFlag && houseActiveArray[index]) {
      uint thisBalance = houseAccountsArray[index];
      houseAccountsArray[index] = 0;
      houseActiveArray[index] = false;

      if (thisBalance > 0) {
        houseMember.send(thisBalance);
      }
    }
    minHouseAccountGet();
  }

  // WITHDRAW AND REMOVE MEMBER
  function houseWithdraw (address payable houseMember) public {
    require(msg.sender == houseMember || msg.sender == owner);
    houseRemoveMember(houseMember);
  }

  // TRANSFER ALL FUNDS TO MEMBERS AND DESTROY THE CONTRACT
  function kill () public {
    require(msg.sender == owner);
    for (uint i = 0; i < maxHouseMembers; i++) {
      houseRemoveMember(houseMemberArray[i]);
    }
    selfdestruct(owner);
  }

  function suspend () public {
    require(msg.sender == owner);
    state = State.Suspended;
  }

  function activate () public {
    require(msg.sender == owner);
    state = State.Active;
  }

  // UTILITY FUNCTIONS

  // COUNT THE MAX NUMBER OF MATCHING SYMBOLS
  function countMaxMatch(uint[numReel] memory outcomeResult) public returns (uint) {
    uint8 max = 0;
    uint8 i = 0;

    for (i = 0; i < numReel; i++) {
        symbolCounter[outcomeResult[i]] = 0;
    }

    for (i = 0; i < numReel; i++) {
      symbolCounter[outcomeResult[i]] += 1;
      if (symbolCounter[outcomeResult[i]] > max) {
        max = symbolCounter[outcomeResult[i]];
      }
    }
    return max;
  }

  // GET THE INDEX OF A HOUSE MEMBER FROM THE ADDRESS IF IT EXISTS
  function indexFromAddressGet(address payable possibleMemberAddress) public view returns (bool, uint8) {
    for (uint8 i = 0; i < maxHouseMembers; i++) {
      if (houseMemberArray[i] == possibleMemberAddress) {
        return (true, i);
      }
    }
    return (false, 0);
  }

  //  ALLOW OWNER TO SET AMOUNT WHICH MUST EVENLY DIVIDE ALL FUNDS
  function setminDivisor(uint amount) public {
    require(msg.sender == owner);
    minDivisor = amount;
  }

  // GETTERS FOR DEBUGGING
  function outcomeGet(uint id) public view returns (uint[numReel] memory) {
    return outcomes[id];
  }

  function getBalance () view public returns (uint) {
    return address(this).balance;
  }

  function minInvestment () view public returns (uint) {
    return houseAccountMin + ((houseAccountMin * minPercentageIncrease) / 100);
  }

  function houseAccountGet (address payable thisAddress) view public returns (uint) {
    (bool memberFlag, uint index) = indexFromAddressGet(thisAddress);
    if (memberFlag) {
      return houseAccountsArray[index];
    }
    else {
      return 0;
    }
  }
}
