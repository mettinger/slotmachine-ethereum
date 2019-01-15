var SlotMachine = artifacts.require("SlotMachine");

module.exports = function(deployer) {
    // deployment steps
    deployer.deploy(SlotMachine);
};
