// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
    using SafeMath for uint256;

    // ------------------------------------------ //
    // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
    // ------------------------------------------ //
    uint256 public totalSupply;
    uint256 public decimals = 18;
    string public name = "Test token";
    string public symbol = "TEST";
    mapping(address => uint256) public balanceOf;
     
    // ------------------------------------------ //
    // ----- END: DO NOT EDIT THIS SECTION ------ //  
    // ------------------------------------------ //
    

    // ERC20 allowance
    mapping(address => mapping(address => uint256)) public allowances;

    // ----- Dividend checkpoint variables -----
    uint256 public dividendsPerToken;
    mapping(address => uint256) public dividendsClaimed;
    mapping(address => uint256) public unclaimedDividends;

    // ----- Holder tracking (for interface only, NOT used in dividend loop) -----
    address[] public holders;
    mapping(address => bool) public isHolder;
    mapping(address => uint256) public holderIndex;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /*=======================================
    =            IERC20 METHODS            =
    =======================================*/

    function allowance(address owner, address spender) external view override returns (uint256) {
        return allowances[owner][spender];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowances[from][msg.sender] >= value, "Insufficient allowance");

        allowances[from][msg.sender] = allowances[from][msg.sender].sub(value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        _updateDividend(from);
        _updateDividend(to);

        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);

        // Update holder list (for interface compliance)
        _updateHolders(from, to);

        emit Transfer(from, to, value);
    }

    /*=======================================
    =          IMintableToken METHODS      =
    =======================================*/

    function mint() external payable override {
        require(msg.value > 0, "Must send ETH to mint");
        uint256 amount = msg.value;

        _updateDividend(msg.sender);

        balanceOf[msg.sender] = balanceOf[msg.sender].add(amount);
        totalSupply = totalSupply.add(amount);

        if (!isHolder[msg.sender]) {
            _addHolder(msg.sender);
        }

        emit Transfer(address(0), msg.sender, amount);
    }

    function burn(address payable dest) external override {
        uint256 amount = balanceOf[msg.sender];
        require(amount > 0, "No tokens to burn");

        _updateDividend(msg.sender);

        balanceOf[msg.sender] = 0;
        totalSupply = totalSupply.sub(amount);

        if (isHolder[msg.sender]) {
            _removeHolder(msg.sender);
        }

        emit Transfer(msg.sender, address(0), amount);
        dest.transfer(amount);
    }

    /*=======================================
    =            IDividends METHODS        =
    =======================================*/

    // O(1) — NO LOOPING!
    function recordDividend() external payable override {
        require(msg.value > 0, "Must send ETH for dividend");
        require(totalSupply > 0, "No tokens in circulation");

        dividendsPerToken = dividendsPerToken.add(msg.value.mul(1e18).div(totalSupply));
    }

    function getWithdrawableDividend(address payee) external view override returns (uint256) {
        uint256 owed = balanceOf[payee].mul(dividendsPerToken.sub(dividendsClaimed[payee])).div(1e18);
        return unclaimedDividends[payee].add(owed);
    }

    function withdrawDividend(address payable dest) external override {
        _updateDividend(msg.sender);
        uint256 amount = unclaimedDividends[msg.sender];
        require(amount > 0, "No dividend to withdraw");
        unclaimedDividends[msg.sender] = 0;
        dest.transfer(amount);
    }

    // Holder list functions — now return real data
    function getNumTokenHolders() external view override returns (uint256) {
        return holders.length;
    }

    function getTokenHolder(uint256 index) external view override returns (address) {
        if (index == 0 || index > holders.length) return address(0);
        return holders[index - 1];
    }

    /*=======================================
    =          DIVIDEND & HOLDER HELPERS   =
    =======================================*/

    function _updateDividend(address account) internal {
        if (account == address(0)) return;

        uint256 owed = balanceOf[account]
            .mul(dividendsPerToken.sub(dividendsClaimed[account]))
            .div(1e18);

        unclaimedDividends[account] = unclaimedDividends[account].add(owed);
        dividendsClaimed[account] = dividendsPerToken;
    }

    // Holder list management (for interface only)
    function _addHolder(address holder) internal {
        holders.push(holder);
        isHolder[holder] = true;
        holderIndex[holder] = holders.length - 1;
    }

    function _removeHolder(address holder) internal {
        require(isHolder[holder], "Not a holder");
        uint256 index = holderIndex[holder];
        uint256 lastIndex = holders.length - 1;

        if (index != lastIndex) {
            address lastHolder = holders[lastIndex];
            holders[index] = lastHolder;
            holderIndex[lastHolder] = index;
        }

        holders.pop();
        delete isHolder[holder];
        delete holderIndex[holder];
    }

    function _updateHolders(address from, address to) internal {
        if (balanceOf[from] == 0 && isHolder[from]) {
            _removeHolder(from);
        }
        if (balanceOf[to] > 0 && !isHolder[to]) {
            _addHolder(to);
        }
    }
}