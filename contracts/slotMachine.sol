pragma solidity ^0.5.0;

contract SlotMachine {

  // ******************************
// DEFINE THE MACHINE

  // MACHINE SPECIFIC CONSTANTS AND VARIABLES
  uint8 constant numReel = 5;

  // DEFINE THE PROBABILITIES FOR THE REEL SYMBOLS
  function makeMachine() internal {
    reels[0].probDenominator = 1000;
    reels[0].probs = [518, 192, 101, 41, 36, 32, 31, 29, 17, 3];
    reels[0].eventLabels = [8, 6, 5, 13, 2, 9, 0, 15, 18, 7];
    reels[1].probDenominator = 1000;
    reels[1].probs = [383, 213, 137, 79, 63, 51, 21, 20, 17, 16];
    reels[1].eventLabels = [13, 8, 0, 15, 9, 16, 2, 14, 17, 5];
    reels[2].probDenominator = 1000;
    reels[2].probs = [238, 154, 146, 104, 83, 83, 82, 80, 16, 14];
    reels[2].eventLabels = [8, 9, 6, 3, 17, 11, 10, 0, 2, 12];
    reels[3].probDenominator = 1000;
    reels[3].probs = [310, 236, 104, 100, 84, 68, 47, 30, 17, 4];
    reels[3].eventLabels = [17, 16, 2, 12, 13, 3, 5, 8, 15, 1];
    reels[4].probDenominator = 1000;
    reels[4].probs = [260, 222, 146, 98, 92, 92, 54, 20, 14, 2];
    reels[4].eventLabels = [13, 16, 2, 15, 11, 19, 5, 0, 12, 8];
}

  // CALCULATE THE PAYOUT
  function paytable(uint[numReel] memory outcome, uint betAmount) internal returns (uint) {
    uint maxMatch = countMaxMatch(outcome);
    if (maxMatch == 4) {
      return betAmount * 75;
    }
    if (maxMatch == 5) {
      return betAmount * 284214;
    }
}

// END MACHINE DEFINITION
// ***************************************

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
    uint thisHash = uint(keccak256(abi.encodePacked(block.number, msg.sender)));
    uint runningProbSum;

    for (uint i = 0; i < numReel; i++) {
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
    require(msg.value <= address(this).balance/maxBetAsBalancePercentage);
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
      uint award = paytable(thisOutcome, bet.amount);
      if (award > 0) {
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
    for (uint i = 0; i < numReel; i++) {
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
