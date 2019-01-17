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
  uint constant maxHouseMembers = 20; // max number of investors/owners
  uint constant minPercentageIncrease = 20; // min overage for kicking someone on funding
  uint constant blockDelay = 0; // 0 for debugging, 3 for production
  uint public minBet = 1;
  uint public maxBetAsBalancePercentage = 10;  // percentage of house max bet


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

  function wager () payable public {
    require(msg.value >= minBet);
    require(msg.value <= address(this).balance/maxBetAsBalancePercentage);
    bets[counter] = Bet(msg.sender, msg.value, block.number + blockDelay);
    emit BetPlaced(msg.sender, msg.value, block.number + 3, counter);
    counter++;
  }

  function random(uint modulus) internal returns (uint) {
    uint randomnumber = uint(keccak256(abi.encodePacked(block.number, msg.sender, nonceForRandom))) % modulus;
    nonceForRandom++;
    return randomnumber;
  }

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

  function spin (uint id) public {
      Bet storage bet = bets[id];
      require(msg.sender == bet.user);
      require(block.number >= bet.block);
      require(block.number <= bet.block + 255); // make this into a refund
      require(!spun[id]);

      outcomeDetermine(id);

      spun[id] = true;
      uint award = paytable(thisOutcome, bet.amount);
      if (award > 0) {
        msg.sender.transfer(award);
      }

      // CUSTOMIZE THIS EVENT FOR THE MACHINE STRUCTURE
      emit Spin(id, thisOutcome[0], thisOutcome[1], award);
  }

  // GETTERS FOR DEBUGGING
  function outcomeGet(uint id) public view returns (uint[numReel] memory) {
    return outcomes[id];
  }

  // TRY TO ADD A NEW MEMBER (OWNER/INVESTOR)
  function addMember(address payable addressToAdd, uint initialFund) private {

    uint currentMin = houseAccounts[houseMemberArray[0]];
    uint currentMinIndex = 0;
    address payable thisAddress;

    for (uint i = 0; i < maxHouseMembers; i++){
      thisAddress = houseMemberArray[i];
      if (houseAccounts[thisAddress] == 0) {
          houseRemoveMember(thisAddress);
          houseMemberArray[i] = addressToAdd;
          houseAccounts[thisAddress] = initialFund;
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
    require(0 == 1);
  }

  // FUND THE CASINO
  function fund () public payable {
    addMember(msg.sender, msg.value);
    calculateHousePercentages();
  }

  // RECALULATE ALL OWNERSHIP PERCENTAGES
  function calculateHousePercentages() public {
    for (uint i = 0; i < maxHouseMembers; i++) {
      housePercentages[houseMemberArray[i]].numerator = houseAccounts[houseMemberArray[i]];
      housePercentages[houseMemberArray[i]].denominator = address(this).balance;
    }
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

  function getBalance () view public returns (uint) {
    return address(this).balance;
  }

  // TRANSFER ALL FUNDS TO MEMBERS AND DESTROY THE CONTRACT
  function kill () public {
    require(msg.sender == owner);
    for (uint i = 0; i < maxHouseMembers; i++) {
      houseRemoveMember(houseMemberArray[i]);
    }
    selfdestruct(owner);
  }
}
