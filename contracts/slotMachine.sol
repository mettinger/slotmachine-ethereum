pragma solidity ^0.5.0;

contract SlotMachine {

  // STRUCTURES
  struct Reel {
    uint probDenominator;
    //  THESE CUTOFFS CORRESPOND TO THE PROBABILITIES OF THE EVENTS
    //  WHEN WE GENERATE A RANDOM NUMBER IN [0, probDenominator - 1]
    uint[] probCutoffs;
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
  mapping(uint => uint[numReel]) public outcomes;
  uint[numReel] thisOutcome;
  mapping(uint => bool) public spun;
  mapping(address => HousePercentage) public housePercentages;
  mapping(address => uint) public houseAccounts;
  address payable [maxHouseMembers] public houseMemberArray;
  uint public counter = 0;
  uint public nonceForRandom = 0;

  // ******************************
  // DEFINE THE MACHINE

  // machine specific constants
  uint8 constant numReel = 2;

  uint[numReel] public numSymbols;
  Reel[numReel] public machine;

  // CALCULATE THE PAYOUT
  function paytable(uint[numReel] memory outcome, uint betAmount) internal pure returns (uint) {
    if (outcome[0] == 0 && outcome[1] == 1) {
      return 5 * betAmount;
    }
    else {
      return 0;
    }
  }

  // DEFINE THE PROBABILITIES FOR THE REEL SYMBOLS
  function makeMachine() internal {
    machine[0].probDenominator = 100;
    machine[0].probCutoffs = [49,97,98,99];

    machine[1].probDenominator = 100;
    machine[1].probCutoffs = [1,2,50,99];

    // check that last cutoff is the max random number
    for (uint8 i = 0; i < numReel; i++) {
      require(machine[i].probCutoffs[machine[i].probCutoffs.length - 1] ==
              machine[i].probDenominator - 1);
    }

    // record the number of symbols for each reel
    for (uint8 i = 0; i < numReel; i++) {
      numSymbols[i] = machine[i].probCutoffs.length;
    }
  }

  event Spin(uint id, uint real0, uint real1, uint award); // specific to machine!
  // ***************************************

  event BetPlaced(address user, uint amount, uint block, uint counter);

  constructor () public payable {
    owner = msg.sender;
    makeMachine();
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

  // GENERATE A RANDOM INTEGER MODULO THE INPUT
  function random(uint modulus) internal returns (uint) {
    uint randomnumber = uint(keccak256(abi.encodePacked(block.number, msg.sender, nonceForRandom))) % modulus;
    nonceForRandom++;
    return randomnumber;
  }

  // DETERMINE THE OUTCOME SYMBOL FOR EACH REEL
  function outcomeDetermine(uint id) public {
    uint thisRandom;

    for (uint i = 0; i < numReel; i++) {
      thisRandom = random(machine[i].probDenominator);
      // CONVERT RANDOM NUMBER TO EVENT
      for (uint j = 0; j < machine[i].probCutoffs.length; j++){
        if (thisRandom <= machine[i].probCutoffs[j]) {
          thisOutcome[i] = j;
          break;
        }
      }
    }
    outcomes[id] = thisOutcome;
  }

  // SPIN THE REELS AND PAYOUT
  function spin (uint id) public {
      Bet storage bet = bets[id];
      require(msg.sender == bet.user);
      require(block.number >= bet.block);
      require(block.number <= bet.block + 255); // make this into a refund
      require(!spun[id]);

      outcomeDetermine(id);

      spun[id] = true;
      uint award = paytable(thisOutcome, bet.amount);
      distributeAmount(false);
      if (award > 0) {
        msg.sender.transfer(award);
      }

      // CUSTOMIZE THIS EVENT FOR THE MACHINE STRUCTURE
      emit Spin(id, thisOutcome[0], thisOutcome[1], award);
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
