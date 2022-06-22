//SPDX-License-Identifier: LICENSED
pragma solidity ^0.7.0;
import "./MultiSigOwner.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/ERC20Interface.sol";

contract JulDAirdrop is MultiSigOwner {
    using SafeMath for uint256;
    uint256 public depositStartDate;
    uint256 public depositEndDate;
    uint256 public withdrawStartDate;
    uint256 public withdrawDuration;
    address public juldAddress;
    address public okseAddress;
    uint256 public swapRate; // 250/1000
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
    event AdminBurn(address adminAddress, uint256 amount);
    event AddressUpdated(address juldAddress, address okseAddress);
    event TimesAndSwapRateUpdated(
        uint256 depositStartDate,
        uint256 depositEndDate,
        uint256 withdrawStartDate,
        uint256 withdrawDuration,
        uint256 swapRate
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

    modifier adminBurnEnable() {
        uint256 curTime = block.timestamp;
        require(curTime > getWithdrawEndDate(), "burn not allowed now");
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
        uint256 amount = getWidrawableAmount(userAddress);
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
    function adminDeposit(bytes calldata signData, bytes calldata keys)
        external
        nonReentrant
        adminDepositEnable
        validSignOfOwner(signData, keys, "adminDeposit")
    {
        (, , , bytes memory params) = abi.decode(
            signData,
            (bytes4, uint256, uint256, bytes)
        );
        uint256 amount = abi.decode(params, (uint256));

        address userAddress = msg.sender;
        TransferHelper.safeTransferFrom(
            okseAddress,
            userAddress,
            address(this),
            amount
        );
        adminDeposited = true;
        emit AdminDeposit(userAddress, amount);
    }

    function adminBurnRemained(bytes calldata signData, bytes calldata keys)
        external
        nonReentrant
        adminBurnEnable
        validSignOfOwner(signData, keys, "adminBurnRemained")
    {
        address DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
        uint256 amount = ERC20Interface(okseAddress).balanceOf(address(this));
        TransferHelper.safeTransfer(okseAddress, DEAD_ADDRESS, amount);
    }

    // verified
    function setTimesAndSwapRate(bytes calldata signData, bytes calldata keys)
        external
        nonReentrant
        validSignOfOwner(signData, keys, "setTimesAndSwapRate")
    {
        (, , , bytes memory params) = abi.decode(
            signData,
            (bytes4, uint256, uint256, bytes)
        );

        (
            uint256 _depositStartDate,
            uint256 _depositEndDate,
            uint256 _withdrawStartDate,
            uint256 _withdrawDuration,
            uint256 _swapRate
        ) = abi.decode(params, (uint256, uint256, uint256, uint256, uint256));
        require(_depositEndDate > _depositStartDate, "deposit time invalid");
        require(
            _withdrawStartDate > _depositEndDate,
            "withdraw start time invalid"
        );
        require(
            _depositEndDate.add(_withdrawDuration) > _withdrawStartDate,
            "withdraw duration invalid"
        );
        depositStartDate = _depositStartDate;
        depositEndDate = _depositEndDate;
        withdrawStartDate = _withdrawStartDate;
        withdrawDuration = _withdrawDuration;
        swapRate = _swapRate;
        emit TimesAndSwapRateUpdated(
            depositStartDate,
            depositEndDate,
            withdrawStartDate,
            withdrawDuration,
            swapRate
        );
    }

    // verified
    function setTokenAddress(bytes calldata signData, bytes calldata keys)
        external
        nonReentrant
        validSignOfOwner(signData, keys, "setTokenAddress")
    {
        (, , , bytes memory params) = abi.decode(
            signData,
            (bytes4, uint256, uint256, bytes)
        );

        (address _juldAddress, address _okseAddress) = abi.decode(
            params,
            (address, address)
        );

        juldAddress = _juldAddress;
        okseAddress = _okseAddress;
        emit AddressUpdated(juldAddress, okseAddress);
    }

    function getBlockTime() public view returns (uint256) {
        return block.timestamp;
    }

    function getWithdrawEndDate() public view returns (uint256) {
        return depositEndDate.add(withdrawDuration);
    }

    function getWidrawableAmount(address userAddress)
        public
        view
        returns (uint256)
    {
        if(!adminDeposited) return 0;
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
