pragma solidity ^0.5.0;

contract SlotMachine {

  // ******************************
  // DEFINE THE MACHINE

  // MACHINE SPECIFIC CONSTANTS AND VARIABLES
  uint8 constant numReel = 5;

  // DEFINE THE PROBABILITIES FOR THE REEL SYMBOLS
  function makeMachine() internal {
    reels[0].probDenominator = 1000;
    reels[0].probs = [325, 180, 140, 104, 52, 48, 42, 39, 36, 34];
    reels[0].eventLabels = [18, 8, 10, 7, 0, 9, 19, 14, 13, 3];
    reels[1].probDenominator = 1000;
    reels[1].probs = [282, 190, 169, 166, 105, 40, 29, 11, 5, 3];
    reels[1].eventLabels = [0, 10, 17, 19, 14, 6, 11, 7, 4, 15];
    reels[2].probDenominator = 1000;
    reels[2].probs = [267, 199, 125, 124, 83, 80, 80, 25, 12, 5];
    reels[2].eventLabels = [14, 12, 16, 13, 8, 3, 6, 0, 18, 5];
    reels[3].probDenominator = 1000;
    reels[3].probs = [244, 233, 103, 86, 82, 80, 62, 62, 46, 2];
    reels[3].eventLabels = [5, 19, 2, 16, 11, 1, 17, 0, 13, 4];
    reels[4].probDenominator = 1000;
    reels[4].probs = [417, 192, 113, 101, 82, 63, 17, 7, 5, 3];
    reels[4].eventLabels = [12, 17, 11, 3, 2, 13, 10, 19, 8, 16];

  }

  // CALCULATE THE PAYOUT
  function paytable(uint[numReel] memory outcome, uint betAmount) internal pure returns (uint) {
    if (outcome[0] == 0 && outcome[1] == 1) {
      return 5 * betAmount;
    }
    else {
      return 0;
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

  // DEFINE EVENTS
  event BetPlaced(address user, uint amount, uint block, uint counter);
  event Awarded(uint id, uint award);
  event Spin(uint id, uint award);

  constructor () public payable {
    owner = msg.sender;
    makeMachine();
  }

  // DETERMINE THE OUTCOME SYMBOL FOR EACH REEL
  //  **********  possible to do in log(precision) rather than O(reel length) ?
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

  function countMaxMatch(uint[numReel] thisOutcome) public pure returns (uint) {
    mapping(uint8 => uint8) public symbolCounter;
    for (uint i = 0; i < numReel; i++) {
      
    }
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
