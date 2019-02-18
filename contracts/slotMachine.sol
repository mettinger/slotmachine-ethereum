pragma solidity ^0.5.0;

contract SlotMachine {

  // ******************************
// DEFINE THE MACHINE

  // MACHINE SPECIFIC CONSTANTS AND VARIABLES
  uint8 constant numReel = 5;

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
      return betAmount * 27;
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

  struct HousePercentage {
    uint numerator;
    uint denominator;
  }

  // PARAMETERS
  uint constant public maxHouseMembers = 20; // max number of investors/owners
  uint constant public minPercentageIncrease = 20; // min overage for kicking someone on funding
  uint constant public blockDelay = 0; // 0 for debugging, 3 for production
  uint constant public maxBetAsBalancePercentage = 10;  // percentage of house max bet
  uint public minFundDivisor = 1000000000;
  uint public minBetDivisor = minFundDivisor;


  // VARIABLES
  address payable public owner;
  mapping(uint => Bet) public bets;
  mapping(uint => bool) public alreadyPlayed;
  mapping(address => HousePercentage) public housePercentages;
  mapping(address => uint) public houseAccounts;
  address payable [maxHouseMembers] public houseMemberArray;
  uint public counter = 0;
  uint public nonceForRandom = 0;
  Reel[numReel] public reels;
  uint[numReel] thisOutcome;
  mapping(uint => uint[numReel]) public outcomes;
  mapping(uint => uint8) public symbolCounter;
  uint public award;

  // DEFINE EVENTS
  event BetPlaced(address user, uint amount, uint block, uint counter);
  event Awarded(uint id, uint award);
  event Spin(uint id, uint award);

  constructor () public payable {
    owner = msg.sender;
    makeMachine();
  }

  // DETERMINE THE OUTCOME SYMBOL FOR EACH REEL
  function sample(uint id) public {
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
  function distributeAmount(bool bet) internal {
    uint numer;
    uint denom;

    for (uint i = 0; i < maxHouseMembers; i++) {
      numer = housePercentages[houseMemberArray[i]].numerator;
      denom = housePercentages[houseMemberArray[i]].denominator;

      // INCOMING BET
      if (bet) {
        houseAccounts[houseMemberArray[i]] += (msg.value * numer)/denom;
      }
      // OUTGOING PAYOUT
      else {
        houseAccounts[houseMemberArray[i]] -= (msg.value * numer)/denom;
      }
    }
  }

  // PLACE A WAGER
  function wager () payable public {
    require(msg.value % minBetDivisor == 0);
    require(msg.value <= (address(this).balance * maxBetAsBalancePercentage) / 100);
    bets[counter] = Bet(msg.sender, msg.value, block.number + blockDelay);
    distributeAmount(true);
    emit BetPlaced(msg.sender, msg.value, block.number + 3, counter);
    counter++;
  }

  // PLAY THE GAME
  function play (uint id) public {
      Bet storage bet = bets[id];
      require(msg.sender == bet.user);
      require(block.number >= bet.block);
      require(block.number <= bet.block + 255); // make this into a refund
      require(!alreadyPlayed[id]);

      sample(id);

      alreadyPlayed[id] = true;
      award = paytable(thisOutcome, bet.amount);
      if (award > 0) {
        if (award > address(this).balance) {
          award = address(this).balance;
        }
        distributeAmount(false);
        msg.sender.transfer(award);
      }

      emit Awarded(id, award);
  }

  // TRY TO ADD A NEW MEMBER (OWNER/INVESTOR)
  function addMember(address payable addressToAdd, uint initialFund) private {

    uint currentMin = houseAccounts[houseMemberArray[0]];
    uint currentMinIndex = 0;
    address payable thisAddress;

    // CHECK IF ALREADY A MEMBER
    for (uint i = 0; i < maxHouseMembers; i++){
      thisAddress = houseMemberArray[i];
      if (thisAddress == addressToAdd) {
          houseAccounts[addressToAdd] += initialFund;
          calculateHousePercentages();
          return;
      }
    }

    // CHECK IF ANY EMPTY SLOTS
    for (uint i = 0; i < maxHouseMembers; i++){
      thisAddress = houseMemberArray[i];
      if (houseAccounts[thisAddress] == 0) {
          houseMemberArray[i] = addressToAdd;
          houseAccounts[addressToAdd] = initialFund;
          calculateHousePercentages();
          return;
      }
      else {
        if (houseAccounts[houseMemberArray[i]] < currentMin) {
          currentMin = houseAccounts[houseMemberArray[i]];
          currentMinIndex = i;
        }
      }
    }

    // BUMP MIN MEMBER IF INITIAL FUND IS GREATER
    if ( initialFund > currentMin + ((currentMin * minPercentageIncrease)/100) ) {
      thisAddress = houseMemberArray[currentMinIndex];
      houseRemoveMember(thisAddress);
      houseMemberArray[currentMinIndex] = addressToAdd;
      houseAccounts[thisAddress] = initialFund;
      calculateHousePercentages();
      return;
    }
    else {
      require(0 == 1);
    }
  }

  // EUCLID'S ALGORITHM FOR GREATEST COMMON DIVISOR
  function gcdCalculate(uint a, uint b) public pure returns (uint) {
    uint t;
    while (b != 0) {
      t = b;
      b = a % b;
      a = t;
    }
    return a;
  }

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

  // RECALULATE ALL OWNERSHIP PERCENTAGES
  function calculateHousePercentages() public {
    uint gcd;

    for (uint i = 0; i < maxHouseMembers; i++) {
      if (houseAccounts[houseMemberArray[i]] == 0) {
        housePercentages[houseMemberArray[i]].numerator = 0;
      }
      gcd = gcdCalculate(houseAccounts[houseMemberArray[i]], address(this).balance);

      housePercentages[houseMemberArray[i]].numerator = houseAccounts[houseMemberArray[i]]/gcd;
      housePercentages[houseMemberArray[i]].denominator = address(this).balance/gcd;
    }
  }

  //  ALLOW OWNER TO SET AMOUNT WHICH MUST EVENLY DIVIDE ALL FUNDS
  function setMinFundDivisor(uint amount) public {
    require(msg.sender == owner);
    minFundDivisor = amount;
  }

  // CHECK THAT INITIAL FUND IS MULTIPLE OF minFundDivisor
  function multipleOf(uint amount) public view returns (bool) {
    return amount % minFundDivisor == 0;
  }

  // FUND THE CASINO
  function fund () public payable {
    require(multipleOf(msg.value));
    addMember(msg.sender, msg.value);
    calculateHousePercentages();
  }

  // REMOVE A MEMBER (OWNER/INVESTOR)
  function houseRemoveMember(address payable houseMember) private {
    if (houseAccounts[houseMember] > 0) {
      houseMember.transfer(houseAccounts[houseMember]);
      houseAccounts[houseMember] = 0;
    }
  }

  // WITHDRAW AND REMOVE MEMBER
  function houseWithdraw (address payable houseMember) public {
    require(msg.sender == houseMember || msg.sender == owner);
    houseRemoveMember(houseMember);
    calculateHousePercentages();
  }

  // TRANSFER ALL FUNDS TO MEMBERS AND DESTROY THE CONTRACT
  function kill () public {
    require(msg.sender == owner);
    for (uint i = 0; i < maxHouseMembers; i++) {
      houseRemoveMember(houseMemberArray[i]);
    }
    selfdestruct(owner);
  }

  // GETTERS FOR DEBUGGING
  function outcomeGet(uint id) public view returns (uint[numReel] memory) {
    return outcomes[id];
  }

  function getBalance () view public returns (uint) {
    return address(this).balance;
  }
}
