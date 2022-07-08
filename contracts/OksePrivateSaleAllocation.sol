//SPDX-License-Identifier: LICENSED
pragma solidity ^0.7.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/ERC20Interface.sol";

contract OksePrivateSaleAllocation is Ownable {
    using SafeMath for uint256;
    address public immutable okseAddress;
    uint256 public immutable delayTimeForWithdraw;
    uint256 public immutable withdrawDuration;

    bool public adminDeposited;
    uint256 public startTime;
    uint256 public withdrawedAmount;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    uint256 public constant DepositAmount = 100000000 ether;

    event AdminDeposit(address adminAddress, uint256 amount);
    event AdminWithdraw(address to, uint256 amount);

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "rc");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
    modifier adminDepositEnable() {
        require(!adminDeposited, "already deposited");
        _;
    }
    modifier adminWithdrawEnable() {
        uint256 curTime = block.timestamp;
        require(curTime > startTime && adminDeposited, "no deposited");
        _;
    }

    constructor() {
        _status = _NOT_ENTERED;
        okseAddress = 0x606FB7969fC1b5CAd58e64b12Cf827FB65eE4875;
        withdrawDuration = 94608000; // 36 months
        delayTimeForWithdraw = 94608000 / 3; // 12 months
    }

    function adminDeposit()
        external
        nonReentrant
        adminDepositEnable
        onlyOwner
    {
        uint256 amount = DepositAmount;
        address userAddress = tx.origin;
        TransferHelper.safeTransferFrom(
            okseAddress,
            userAddress,
            address(this),
            amount
        );
        adminDeposited = true;
        startTime = block.timestamp;
        startTime = startTime.add(delayTimeForWithdraw);
        emit AdminDeposit(userAddress, amount);
    }

    function adminWithdraw()
        external
        nonReentrant
        adminWithdrawEnable
        onlyOwner
    {
        uint256 amount = getWithdrawableAmount();
        address to = tx.origin;
        TransferHelper.safeTransfer(okseAddress, to, amount);
        withdrawedAmount = withdrawedAmount.add(amount);
        emit AdminWithdraw(to, amount);
    }

    function getWithdrawableAmount() public view returns (uint256) {
        if(!adminDeposited) return 0;
        uint256 curTime = block.timestamp;
        if (curTime < startTime) return 0;
        if (curTime >= getWithdrawEndDate()) curTime = getWithdrawEndDate();
        uint256 amount = DepositAmount;
        amount = amount.mul(curTime.sub(startTime)).div(withdrawDuration);
        amount = amount.sub(withdrawedAmount);
        return amount;
    }

    function getWithdrawEndDate() public view returns (uint256) {
        require(adminDeposited, "not deposited yet");
        return startTime.add(withdrawDuration);
    }
}
