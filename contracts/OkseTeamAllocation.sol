//SPDX-License-Identifier: LICENSED
pragma solidity ^0.7.0;
import "./MultiSigOwner.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/ERC20Interface.sol";

contract OkseTeamAllocation is MultiSigOwner {
    using SafeMath for uint256;
    address public okseAddress;
    uint256 public delayTimeForWithdraw;
    uint256 public withdrawDuration;

    bool public adminDeposited;
    uint256 public startTime;
    uint256 public withdrawedAmount;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    uint256 public constant DepositAmount = 200000000 ether;

    event AdminDeposit(address adminAddress, uint256 amount);
    event AdminWithdraw(address to, uint256 amount);
    event ParamsUpdated(
        address okseAddress,
        uint256 delayTimeForWithdraw,
        uint256 withdrawDuration
    );
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

    function adminDeposit(bytes calldata signData, bytes calldata keys)
        external
        nonReentrant
        adminDepositEnable
        validSignOfOwner(signData, keys, "adminDeposit")
    {
        uint256 amount = DepositAmount;
        address userAddress = msg.sender;
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

    function adminWithdraw(bytes calldata signData, bytes calldata keys)
        external
        nonReentrant
        adminWithdrawEnable
        validSignOfOwner(signData, keys, "adminWithdraw")
    {
        uint256 amount = getWidrawableAmount();
        address to = msg.sender;
        TransferHelper.safeTransfer(okseAddress, to, amount);
        withdrawedAmount = withdrawedAmount.add(amount);
        emit AdminWithdraw(to, amount);
    }

    function getWidrawableAmount() public view returns (uint256) {
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

    // verified
    function setParams(bytes calldata signData, bytes calldata keys)
        external
        nonReentrant
        validSignOfOwner(signData, keys, "setParams")
    {
        (, , , bytes memory params) = abi.decode(
            signData,
            (bytes4, uint256, uint256, bytes)
        );

        (
            address _okseAddress,
            uint256 _delayTimeForWithdraw,
            uint256 _withdrawDuration
        ) = abi.decode(params, (address, uint256, uint256));

        okseAddress = _okseAddress;
        delayTimeForWithdraw = _delayTimeForWithdraw;
        withdrawDuration = _withdrawDuration;
        emit ParamsUpdated(okseAddress, delayTimeForWithdraw, withdrawDuration);
    }
}
