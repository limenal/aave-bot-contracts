// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.6.12;
import {ILendingPool} from "@aave/protocol-v2/contracts/interfaces/ILendingPool.sol";
import "./IAaveIncentivesController.sol";
import "./ERC20.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router.sol";
contract Redeposit is Ownable{
    
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    /**
     * @dev Token Contracts:
     * {WMATIC} - WMATIC token address
     */
    address constant public WMATIC = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    /**
     * @dev Third Party Contracts:
     * {pool} -  AAVE LendingPool
     * {quickswapRouter} - quickswap router
     * {incentivesController} - AAVE incetives controller
     */
    address constant public pool = address(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);
    address constant public quickswapRouter  = address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    address constant public incentivesController = address(0x357D51124f59836DeD84c8a1730D72B749d8BC23);
    
    /**
     * @dev Contract Variables:
     * {totalDeposits} - The sum of all active deposits including recalculation after swaps | (T)
     * {sumOfRewards} - The sum of (rewards)/(totalDeposits) | (S)
     * {sumOfPreviousRewards} - The sum of all previous rewards that already added to sumOfRewards
     * {totalDepositsNonNormalized} - The sum of all active deposits
     */
    uint256 public totalDeposits;
    uint256 public sumOfRewards;
    uint256 public sumOfPreviousRewards;
    uint256 public totalDepositsNonNormalized;
    /**
     * @dev Current token state:
     * {currentDecimals} - A decimals of current token
     * {currentToken} - Current normal token
     * {currentAaveToken} - Current aave token
     */
    uint8 public currentDecimals;
    address public currentToken;
    address public currentAaveToken;
    
    /**
     * @dev Mappings:
     * {currentDeposit} - All deposits made by users
     * {sumOfRewardsForUser} - A sumOfRewards for users at pool join time
     */
    mapping(address => uint256) public currentDeposit;
    mapping(address => uint256) public sumOfRewardsForUser;
    
    /**
     * @dev Arrays:
     * {path} - The swap path 
     * {assets} - A token to claim rewards
     */
    address[] public path;
    address[] public assets;

    event Deposited(address user, uint256 amount);
    
    event Withdrawn(address user, uint256 amount);
    
    event TokenSet(address newToken, uint256 priceNumerator, uint256 priceDenominator);
    
    /**
     * @dev Contract initializing with {token} and {aToken}
     */
    constructor(address token, address aToken) public
    {
        sumOfPreviousRewards = 0;
        totalDeposits = 0;
        sumOfRewards = 0;
        
        currentToken = token;
        currentAaveToken = aToken;
        
        currentDecimals = IERC20(currentToken).decimals();
        
        IERC20(currentToken).safeApprove(quickswapRouter, 0);
        IERC20(currentToken).safeApprove(quickswapRouter, uint(-1));
        
        IERC20(currentToken).safeApprove(pool, 0);
        IERC20(currentToken).safeApprove(pool, uint(-1));
        
        IERC20(WMATIC).safeApprove(quickswapRouter, 0);
        IERC20(WMATIC).safeApprove(quickswapRouter, uint(-1));
        
    }
    
    /**
     * @dev Sets new contract token
     */
    function setMaxToken(address newToken, address newAaveToken) external onlyOwner{
        require(newToken != currentToken && totalDeposits > 0);
        uint256 quickswapAllowance = IERC20(newToken).allowance(address(this), quickswapRouter);
        if(quickswapAllowance == 0)
        {
            IERC20(newToken).safeApprove(quickswapRouter, 0);
            IERC20(newToken).safeApprove(quickswapRouter, uint(-1));
        }
            
        uint256 aaveAllowance = IERC20(newToken).allowance(address(this), pool);
        if(aaveAllowance == 0)
        {
            IERC20(newToken).safeApprove(pool, 0);
            IERC20(newToken).safeApprove(pool, uint(-1));
        }
        
        uint256 totalDepositsBeforeSwap = IERC20(currentAaveToken).balanceOf(address(this));
        
        ILendingPool(pool).withdraw(currentToken, type(uint).max, address(this));
        
        uint256 balanceBeforeSwap = IERC20(newToken).balanceOf(address(this));

        path = [currentToken, newToken];
        
        IUniswapV2Router01(quickswapRouter).swapExactTokensForTokens(totalDepositsBeforeSwap, 0, path, address(this), now.add(600));
        
        uint256 totalDepositsAfterSwap = IERC20(newToken).balanceOf(address(this)).sub(balanceBeforeSwap);
        
        ILendingPool(pool).deposit(newToken, totalDepositsAfterSwap, address(this), 0);
        
        totalDeposits = totalDeposits.mul(totalDepositsAfterSwap).div(totalDepositsBeforeSwap);
       
        sumOfPreviousRewards = sumOfPreviousRewards.mul(totalDepositsAfterSwap).div(totalDepositsBeforeSwap);
        
        currentToken = newToken;
        currentAaveToken = newAaveToken;
        currentDecimals = IERC20(currentToken).decimals();
        
        emit TokenSet(newToken, totalDepositsAfterSwap, totalDepositsBeforeSwap);
    }
    /**
     * @dev Function that makes the deposits and swaps {token} to current token if necessary
     */
    function deposit(address token, uint256 amount, address user) public {
        require(amount > 0);
        uint256 amountToDeposit;
        if(currentDeposit[user] > 0)
        {
            withdrawToContract(user);
        }
        if(totalDeposits>0)
        {
            distributeUSD(); 
        }
        
        if(token != currentToken)
        {
            IERC20(token).safeTransferFrom(user, address(this), amount);
            
            path = [token, currentToken];
            uint256 quickswapAllowance = IERC20(token).allowance(address(this), quickswapRouter);
            if(quickswapAllowance == 0)
            {
                IERC20(token).safeApprove(quickswapRouter, 0);
                IERC20(token).safeApprove(quickswapRouter, uint(-1));
            }
            IUniswapV2Router01(quickswapRouter).swapExactTokensForTokens(amount, 0, path, address(this), now.add(600));
            amountToDeposit = IERC20(currentToken).balanceOf(address(this));
            ILendingPool(pool).deposit(currentToken, amountToDeposit, address(this), 0);

        }
        else{
            IERC20(currentToken).safeTransferFrom(user, address(this), amount);
            amountToDeposit = IERC20(currentToken).balanceOf(address(this));
            ILendingPool(pool).deposit(currentToken, amountToDeposit, address(this), 0);
            
        }
        // We want to store deposits in same decimals
        if(currentDecimals == 18)
        {
            totalDepositsNonNormalized = totalDepositsNonNormalized.add(amountToDeposit);
            currentDeposit[user] = amountToDeposit;
        }
        else{
            totalDepositsNonNormalized = totalDepositsNonNormalized.add(amountToDeposit.mul(10**12));
            currentDeposit[user] = amountToDeposit.mul(10**12);
        }
        totalDeposits = totalDeposits.add(amountToDeposit);
        sumOfRewardsForUser[user] = sumOfRewards;
        emit Deposited(user, amountToDeposit);
    }
    /**
     * @dev Withdraws funds and sends them to the {{to}}.
     */
    function withdraw(address to) public {
        require(currentDeposit[to] > 0);
        distributeUSD();
        uint256 balanceBeforeWithdraw = IERC20(currentToken).balanceOf(address(this));
        withdrawToContract(to);
        uint256 amountToWithdraw = IERC20(currentToken).balanceOf(address(this)).sub(balanceBeforeWithdraw);
        IERC20(currentToken).safeTransfer(to, amountToWithdraw);
        emit Withdrawn(to, amountToWithdraw);
    }
    /**
     * @dev Calculates amount to deposit then withdraws funds to this contract.
     * 
     */
    function withdrawToContract(address to) internal{
        uint256 depositedPercent = currentDeposit[to].mul(uint256(1 ether)).div(totalDepositsNonNormalized);
        uint256 deposited = totalDeposits.mul(depositedPercent).div(uint256(1 ether));
        uint256 reward = deposited.mul(sumOfRewards.sub(sumOfRewardsForUser[to])).div(uint256(1 ether));
        uint withdrawal = deposited.add(reward);
        ILendingPool(pool).withdraw(currentToken, withdrawal, address(this));
        totalDeposits = totalDeposits.sub(deposited);
        totalDepositsNonNormalized = totalDepositsNonNormalized.sub(currentDeposit[to]);
        sumOfPreviousRewards = sumOfPreviousRewards.sub(reward);
        currentDeposit[to] = 0;

    }
    /**
     * @dev Distributes USD rewards 
     */
    function distributeUSD() internal {
        require(totalDeposits > 0);
        uint256 reward = IERC20(currentAaveToken).balanceOf(address(this)).sub(totalDeposits).sub(sumOfPreviousRewards);
        sumOfPreviousRewards = sumOfPreviousRewards.add(reward);
        sumOfRewards = sumOfRewards.add(uint256(1 ether).mul(reward).div(totalDeposits));
    }
    /**
     * @dev Claims WMATIC rewards then swaps to {currentToken} and deposits
     */
    function distributeMatic() external onlyOwner{
        require(totalDeposits > 0);
        
        assets = [currentAaveToken];
        
        uint256 earned = IAaveIncentivesController(incentivesController).getRewardsBalance(assets, address(this));
        
        IAaveIncentivesController(incentivesController).claimRewards(assets, earned, address(this));
        
        path = [WMATIC, currentToken];
        
        IUniswapV2Router01(quickswapRouter).swapExactTokensForTokens(earned, 0, path, address(this), now.add(600));
        
        uint256 amountToDeposit = IERC20(currentToken).balanceOf(address(this));
        
        ILendingPool(pool).deposit(currentToken, amountToDeposit, address(this), 0);
        
        sumOfRewards = sumOfRewards.add(uint256(1 ether).mul(amountToDeposit).div(totalDeposits));
    }
    
    function getUserReward(address user) public view returns (uint256)
    {
        require(totalDeposits > 0);
        uint256 totalReward = IERC20(currentAaveToken).balanceOf(address(this)).sub(totalDeposits).sub(sumOfPreviousRewards);
        uint256 localSumOfRewards = sumOfRewards.add(uint256(1 ether).mul(totalReward).div(totalDeposits));
        
        uint256 depositedPercent = currentDeposit[user].mul(uint256(1 ether)).div(totalDepositsNonNormalized);
        uint256 deposited = totalDeposits.mul(depositedPercent).div(uint256(1 ether));
        uint256 reward = deposited.mul(localSumOfRewards.sub(sumOfRewardsForUser[user])).div(uint256(1 ether));
        
        uint withdrawal = deposited.add(reward);
        return withdrawal;
    }
    
    function getUserBalance(address user) public view returns (uint256)
    {
        return currentDeposit[user];
    }
    
}
