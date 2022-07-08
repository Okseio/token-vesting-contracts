//SPDX-License-Identifier: LICENSED
pragma solidity ^0.7.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/ERC20Interface.sol";

contract JulDAirdrop is Ownable {
    using SafeMath for uint256;
    uint256 public depositStartDate;
    uint256 public depositEndDate;
    uint256 public withdrawStartDate;
    uint256 public immutable withdrawDuration;
    address public immutable juldAddress;
    address public immutable okseAddress;
    uint256 public immutable swapRate; // 250/1000
    bool public adminDeposited;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    mapping(address => uint256) public userBalances;
    mapping(address => uint256) public userWithdrawAmounts;
    mapping(address => bool) public userWithdrawedJulD;

    event UserDeposit(address userAddress, uint256 amount);
    event UserWithdraw(address userAddress, uint256 amount);
    event UserWithdrawedJuld(address userAddress, uint256 amount);

    event AdminDeposit(address adminAddress, uint256 amount);
    event AdminClaim(address adminAddress, uint256 amount);
    event TimesUpdated(
        uint256 depositStartDate,
        uint256 depositEndDate,
        uint256 withdrawStartDate
    );

    modifier depositEnable() {
        uint256 curTime = block.timestamp;
        require(
            curTime >= depositStartDate && curTime < depositEndDate,
            "deposit not allowed now"
        );
        _;
    }
    modifier withdrawEnable() {
        uint256 curTime = block.timestamp;
        require(
            curTime >= withdrawStartDate && curTime < getWithdrawEndDate(),
            "withdraw not allowed now"
        );
        _;
    }
    modifier juldWithdrawEnable(address userAddress) {
        uint256 curTime = block.timestamp;
        require(curTime > depositEndDate, "juld withdraw not allowed now");
        require(!userWithdrawedJulD[userAddress], "already withdrawed juld");
        _;
    }

    modifier adminClaimEnable() {
        uint256 curTime = block.timestamp;
        require(curTime > getWithdrawEndDate(), "claim not allowed now");
        _;
    }
    modifier adminDepositEnable() {
        uint256 curTime = block.timestamp;
        require(
            curTime >= depositEndDate && curTime < withdrawStartDate,
            "admin deposit not allowed now"
        );
        require(!adminDeposited, "already deposited");
        _;
    }
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

    constructor() {
        _status = _NOT_ENTERED;

        depositStartDate = 1656633600; // 01/07/2022 : 00/00/00
        depositEndDate = 1659312000; // 01/08/2022 : 00/00/00
        withdrawStartDate = 1661990400; // 01/09/2022 : 00/00/00
        withdrawDuration = 94608000; // 36 monthes
        juldAddress = 0x5A41F637C3f7553dBa6dDC2D3cA92641096577ea;
        okseAddress = 0x606FB7969fC1b5CAd58e64b12Cf827FB65eE4875;
        swapRate = 250; // 250/1000
    }

    // verified
    function deposit(uint256 amount) external nonReentrant depositEnable {
        address userAddress = msg.sender;
        TransferHelper.safeTransferFrom(
            juldAddress,
            userAddress,
            address(this),
            amount
        );
        userBalances[userAddress] = userBalances[userAddress].add(amount);
        emit UserDeposit(userAddress, amount);
    }

    // verified
    function withdraw() external nonReentrant withdrawEnable {
        address userAddress = msg.sender;
        uint256 amount = getWithdrawableAmount(userAddress);
        uint256 okseBalance = ERC20Interface(okseAddress).balanceOf(
            address(this)
        );
        require(okseBalance >= amount, "not enough okse");
        TransferHelper.safeTransfer(okseAddress, userAddress, amount);
        userWithdrawAmounts[userAddress] = userWithdrawAmounts[userAddress].add(
            amount
        );
        emit UserWithdraw(userAddress, amount);
    }

    // verified
    function withdrawJulD()
        external
        nonReentrant
        juldWithdrawEnable(msg.sender)
    {
        address userAddress = msg.sender;
        uint256 amount = userBalances[userAddress];
        uint256 juldBalance = ERC20Interface(juldAddress).balanceOf(
            address(this)
        );
        require(juldBalance >= amount, "not enough juld");
        TransferHelper.safeTransfer(juldAddress, userAddress, amount);
        userWithdrawedJulD[userAddress] = true;
        emit UserWithdrawedJuld(userAddress, amount);
    }

    // verified
    function adminDeposit(uint256 amount)
        external
        nonReentrant
        adminDepositEnable
        onlyOwner
    {
        address userAddress = tx.origin;
        TransferHelper.safeTransferFrom(
            okseAddress,
            userAddress,
            address(this),
            amount
        );
        adminDeposited = true;
        emit AdminDeposit(userAddress, amount);
    }

    function adminClaimRemained()
        external
        nonReentrant
        adminClaimEnable
        onlyOwner
    {
        address userAddress = tx.origin;
        uint256 amount = ERC20Interface(okseAddress).balanceOf(address(this));
        TransferHelper.safeTransfer(okseAddress, userAddress, amount);
        emit AdminClaim(userAddress, amount);
    }

    // verified
    function setParams(
        uint256 _depositStartDate,
        uint256 _depositEndDate,
        uint256 _withdrawStartDate
    ) external nonReentrant onlyOwner {
        require(_depositEndDate > _depositStartDate, "deposit time invalid");
        require(
            _withdrawStartDate > _depositEndDate,
            "withdraw start time invalid"
        );
        require(
            _depositEndDate.add(withdrawDuration) > _withdrawStartDate,
            "withdraw date invalid"
        );
        depositStartDate = _depositStartDate;
        depositEndDate = _depositEndDate;
        withdrawStartDate = _withdrawStartDate;
        emit TimesUpdated(depositStartDate, depositEndDate, withdrawStartDate);
    }

    function getBlockTime() public view returns (uint256) {
        return block.timestamp;
    }

    function getWithdrawEndDate() public view returns (uint256) {
        return depositEndDate.add(withdrawDuration);
    }

    function getWithdrawableAmount(address userAddress)
        public
        view
        returns (uint256)
    {
        if (!adminDeposited) return 0;
        uint256 curTime = block.timestamp;
        if (curTime < withdrawStartDate) return 0;
        if (curTime >= getWithdrawEndDate()) return 0;
        uint256 amount = userBalances[userAddress];
        amount = amount.mul(swapRate).div(1000);
        amount = amount.mul(curTime.sub(depositEndDate)).div(withdrawDuration);
        amount = amount.sub(userWithdrawAmounts[userAddress]);
        return amount;
    }
}
