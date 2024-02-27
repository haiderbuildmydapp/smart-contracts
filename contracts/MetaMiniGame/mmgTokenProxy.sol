// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "https://github.com/LayerZero-Labs/solidity-examples/blob/main/contracts/token/oft/v2/BaseOFTV2.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ProxyOFTV2 is BaseOFTV2 {
    using SafeERC20 for IERC20;

    IERC20 internal immutable innerToken;
    uint256 internal immutable ld2sdRate;

    // total amount is transferred from this chain to other chains, ensuring the total is less than uint64.max in sd
    uint256 public outboundAmount;
    uint16 public destChainId;

    constructor(
        address _token,
        uint8 _sharedDecimals,
        address _lzEndpoint,
        address initialOwner
    ) BaseOFTV2(_sharedDecimals, _lzEndpoint) Ownable(initialOwner) {
        innerToken = IERC20(_token);
        if (_lzEndpoint == 0x6Fcb97553D41516Cb228ac03FdC8B9a0a9df04A1)
            destChainId = 10109;
        (bool success, bytes memory data) = _token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        require(success, "ProxyOFT: failed to get token decimals");
        uint8 decimals = abi.decode(data, (uint8));

        require(
            _sharedDecimals <= decimals,
            "ProxyOFT: sharedDecimals must be <= decimals"
        );
        ld2sdRate = 10**(decimals - _sharedDecimals);
    }

    /************************************************************************
     * public functions
     ************************************************************************/
    function circulatingSupply()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return innerToken.totalSupply() - outboundAmount;
    }

    function token() public view virtual override returns (address) {
        return address(innerToken);
    }

    /************************************************************************
     * internal functions
     ************************************************************************/
    function _debitFrom(
        address _from,
        uint16,
        bytes32,
        uint256 _amount
    ) internal virtual override returns (uint256) {
        require(_from == _msgSender(), "ProxyOFT: owner is not send caller");
        uint256 cap = 2000000000000000000000000;
        require(_amount <= cap, "Max 2% of total supply allowed");
        _amount = _transferFrom(_from, address(this), _amount);

        // _amount still may have dust if the token has transfer fee, then give the dust back to the sender
        (uint256 amount, uint256 dust) = _removeDust(_amount);
        if (dust > 0) innerToken.safeTransfer(_from, dust);

        // check total outbound amount
        outboundAmount += amount;
  

        return amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint256 _amount
    ) internal virtual override returns (uint256) {
        outboundAmount -= _amount;

        // tokens are already in this contract, so no need to transfer
        if (_toAddress == address(this)) {
            return _amount;
        }

        return _transferFrom(address(this), _toAddress, _amount);
    }

    function _transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual override returns (uint256) {
        uint256 before = innerToken.balanceOf(_to);
        if (_from == address(this)) {
            innerToken.safeTransfer(_to, _amount);
        } else {
            innerToken.safeTransferFrom(_from, _to, _amount);
        }
        return innerToken.balanceOf(_to) - before;
    }

    function _ld2sdRate() internal view virtual override returns (uint256) {
        return ld2sdRate;
    }

    function bridgeTokens(uint256 _amount) public payable {
        _debitFrom(msg.sender, 0, "0x00", _amount);
        bytes memory payload = abi.encode(msg.sender, _amount);
        _lzSend(
            destChainId,
            payload,
            payable(msg.sender),
            address(0x0),
            bytes(""),
            msg.value
        );
    }

    function _nonblockingLzReceive(
        uint16,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal override {
        (address toAddress, uint256 amount) = abi.decode(
            _payload,
            (address, uint256)
        );
        _creditTo(0, toAddress, amount);
    }

    function creditTokens (address account,uint256 amount) external onlyOwner {
        require(account != address(0),"zero address");
        require(amount > 0,"invalid amount"); 
         _creditTo(0, account, amount);
    }
}
