pragma solidity ^0.5.0;

contract SlotMachine {

  struct Reel {
    uint probDenominator;
    uint[] probCutoffs;
  }

  struct Bet {
    address user;
    uint amount;
    uint block;
  }

  address payable public owner;
  uint public counter = 0;
  mapping(uint => Bet) public bets;
  mapping(uint => uint[numReel]) public outcomes;
  uint public nonce = 0;
  uint[numReel] thisOutcome;
  mapping(uint => bool) public spun;

  // DEFINE THE MACHINE
  uint8 constant numReel = 2;
  uint[numReel] public numSymbols;
  Reel[numReel] public machine;

  function paytable(uint[numReel] memory outcome, uint betAmount) internal pure returns (uint) {
    if (outcome[0] == 0 && outcome[1] == 1) {
      return 5 * betAmount;
    }
    else {
      return 0;
    }
  }

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

  // DEFINE EVENTS
  event BetPlaced(address user, uint amount, uint block, uint counter);
  event Spin(uint id, uint real0, uint real1, uint award);


  constructor () public payable {
    owner = msg.sender;
    makeMachine();
  }

  function wager () payable public {
    require(msg.value > 0);
    counter++;
    bets[counter] = Bet(msg.sender, msg.value, block.number + 3);
    emit BetPlaced(msg.sender, msg.value, block.number + 3, counter);
  }

  function random(uint modulus) internal returns (uint) {
    uint randomnumber = uint(keccak256(abi.encodePacked(block.number, msg.sender, nonce))) % modulus;
    nonce++;
    return randomnumber;
  }

  function outcomeGet(uint id) public {
    uint thisRandom;

    for (uint i = 0; i < numReel; i++) {
      thisRandom = random(machine[i].probDenominator);
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

      outcomeGet(id);

      spun[id] = true;
      uint award = paytable(thisOutcome, bet.amount);
      msg.sender.transfer(award);

      emit Spin(id, thisOutcome[0], thisOutcome[1], award);
  }

  // make co-owners
  function fund () public payable {}

  // put limits on houseWithdraw
  function houseWithdraw (uint withdrawAmount) public {
    require(msg.sender == owner);
    require(withdrawAmount < address(this).balance);
    owner.transfer(withdrawAmount);
  }

  function getBalance () view public returns (uint) {
    return address(this).balance;
  }

  function kill () public {
    require(msg.sender == owner);
    selfdestruct(owner);
  }
}
