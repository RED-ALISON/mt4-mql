/**
 * XMT-Scalper resurrected
 *
 *
 * This EA is originally based on the famous "MillionDollarPips EA". The core idea of the strategy is scalping based on a
 * reversal from a channel breakout. Over the years it has gone through multiple transformations. Today various versions with
 * different names circulate in the internet (MDP-Plus, XMT-Scalper, Assar). None of them is suitable for real trading, mainly
 * due to lack of signal documentation and a significant amount of issues in the program logic.
 *
 * This version is a complete rewrite.
 *
 * Sources:
 *  @link  https://github.com/rosasurfer/mt4-mql/blob/a1b22d0/mql4/experts/mdp#             [MillionDollarPips v2 decompiled]
 *  @link  https://github.com/rosasurfer/mt4-mql/blob/36f494e/mql4/experts/mdp#                    [MDP-Plus v2.2 by Capella]
 *  @link  https://github.com/rosasurfer/mt4-mql/blob/23c51cc/mql4/experts/mdp#                   [MDP-Plus v2.23 by Capella]
 *  @link  https://github.com/rosasurfer/mt4-mql/blob/a0c2411/mql4/experts/mdp#                [XMT-Scalper v2.41 by Capella]
 *  @link  https://github.com/rosasurfer/mt4-mql/blob/8f5f29e/mql4/experts/mdp#                [XMT-Scalper v2.42 by Capella]
 *  @link  https://github.com/rosasurfer/mt4-mql/blob/513f52c/mql4/experts/mdp#                [XMT-Scalper v2.46 by Capella]
 *  @link  https://github.com/rosasurfer/mt4-mql/blob/b3be98e/mql4/experts/mdp#               [XMT-Scalper v2.461 by Capella]
 *  @link  https://github.com/rosasurfer/mt4-mql/blob/41237e0/mql4/experts/mdp#               [XMT-Scalper v2.522 by Capella]
 *
 * Changes:
 *  - removed MQL5 syntax and fixed compiler issues
 *  - converted code to use the rosasurfer framework
 *  - moved all print output to the framework logger
 *  - removed obsolete order expiration, NDD and screenshot functionality
 *  - removed obsolete sending of fake orders and measuring of execution times
 *  - removed broken commission calculations
 *  - removed obsolete functions and variables
 *  - added internal order management (huge speed improvement)
 *  - added monitoring of PositionOpen and PositionClose events
 *  - fixed position size calculation
 *  - fixed signal detection and added input parameter ChannelBug (for comparison only)
 *  - fixed TakeProfit calculation and added input parameter TakeProfitBug (for comparison only)
 *  - fixed trade management issues
 *  - restructured and reorganized input parameters
 *  - rewrote status display
 */
#include <stddefines.mqh>
int   __InitFlags[] = {INIT_TIMEZONE, INIT_PIPVALUE, INIT_BUFFERED_LOG};
int __DeinitFlags[];

////////////////////////////////////////////////////// Configuration ////////////////////////////////////////////////////////

extern string ___a___________________________ = "=== Entry indicator: 1=MovingAverage, 2=BollingerBands, 3=Envelopes ===";
extern int    EntryIndicator                  = 1;          // entry signal indicator for price channel calculation
extern int    IndicatorTimeFrame              = PERIOD_M1;  // entry indicator timeframe
extern int    IndicatorPeriods                = 3;          // entry indicator bar periods
extern double BollingerBands.Deviation        = 2;          // standard deviations
extern double Envelopes.Deviation             = 0.07;       // in percent

extern string ___b___________________________ = "=== Entry bar size conditions ================";
extern bool   UseSpreadMultiplier             = true;       // use spread multiplier or fixed min. bar size
extern double SpreadMultiplier                = 12.5;       // min. bar size = SpreadMultiplier * avgSpread
extern double MinBarSize                      = 18;         // min. bar size in {pip}

extern string ___c___________________________ = "=== Signal settings ========================";
extern double BreakoutReversal                = 0;          // required reversal in {pip} (0: counter-trend trading w/o reversal)
extern double MaxSpread                       = 2;          // max. acceptable spread in {pip}
extern bool   ReverseSignals                  = false;      // Buy => Sell, Sell => Buy

extern string ___d___________________________ = "=== MoneyManagement ====================";
extern bool   MoneyManagement                 = true;       // TRUE: calculate lots dynamically; FALSE: use "ManualLotsize"
extern double Risk                            = 2;          // percent of equity to risk with each trade
extern double ManualLotsize                   = 0.01;       // fix position to use if "MoneyManagement" is FALSE

extern string ___e___________________________ = "=== Trade settings ========================";
extern double TakeProfit                      = 10;         // TP in {pip}
extern double StopLoss                        = 6;          // SL in {pip}
extern double TrailEntryStep                  = 1;          // trail entry limits every {pip}
extern double TrailExitStart                  = 0;          // start trailing exit limits after {pip} in profit
extern double TrailExitStep                   = 2;          // trail exit limits every {pip} in profit
extern int    Magic                           = 0;          // if zero the MagicNumber is generated
extern double MaxSlippage                     = 0.3;        // max. acceptable slippage in {pip}

extern string ___f___________________________ = "=== Overall PL settings =====================";
extern double EA.StopOnProfit                 = 0;          // stop on overall profit in {money} (0: no stop)
extern double EA.StopOnLoss                   = 0;          // stop on overall loss in {money} (0: no stop)

extern string ___g___________________________ = "=== Bugs ================================";
extern bool   ChannelBug                      = false;      // enable erroneous calculation of the breakout channel (for comparison only)
extern bool   TakeProfitBug                   = true;       // enable erroneous calculation of TakeProfit targets (for comparison only)

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/expert.mqh>
#include <stdfunctions.mqh>
#include <rsfLibs.mqh>
#include <functions/JoinStrings.mqh>
#include <structs/rsf/OrderExecution.mqh>

#define SIGNAL_LONG     1
#define SIGNAL_SHORT    2


// order log
int      orders.ticket      [];
double   orders.lots        [];        // order volume > 0
int      orders.pendingType [];        // pending order type if applicable or OP_UNDEFINED (-1)
double   orders.pendingPrice[];        // pending entry limit if applicable or 0
int      orders.openType    [];        // order open type of an opened position or OP_UNDEFINED (-1)
datetime orders.openTime    [];        // order open time of an opened position or 0
double   orders.openPrice   [];        // order open price of an opened position or 0
datetime orders.closeTime   [];        // order close time of a closed order or 0
double   orders.closePrice  [];        // order close price of a closed position or 0
double   orders.stopLoss    [];        // SL price or 0
double   orders.takeProfit  [];        // TP price or 0
double   orders.swap        [];        // order swap
double   orders.commission  [];        // order commission
double   orders.profit      [];        // order profit (gross)

// order statistics
bool     isOpenOrder;                  // whether an open order exists (max. 1 open order)
bool     isOpenPosition;               // whether an open position exists (max. 1 open position)

double   openLots;                     // total open lotsize: -n...+n
double   openSwap;                     // total open swap
double   openCommission;               // total open commissions
double   openPl;                       // total open gross profit
double   openPlNet;                    // total open net profit

int      closedPositions;              // number of closed positions
double   closedLots;                   // total closed lotsize: 0...+n
double   closedSwap;                   // total closed swap
double   closedCommission;             // total closed commission
double   closedPl;                     // total closed gross profit
double   closedPlNet;                  // total closed net profit

double   totalPlNet;                   // openPlNet + closedPlNet

// other
double   currentSpread;                // current spread in pip
double   avgSpread;                    // average spread in pip
double   minBarSize;                   // min. bar size in absolute terms
int      orderSlippage;                // order slippage in point
string   orderComment = "";

// cache vars to speed-up ShowStatus()
string   sCurrentSpread  = "-";
string   sAvgSpread      = "-";
string   sMaxSpread      = "-";
string   sCurrentBarSize = "-";
string   sMinBarSize     = "-";
string   sIndicator      = "-";
string   sUnitSize       = "-";


/**
 * Initialization
 *
 * @return int - error status
 */
int onInit() {
   // validate inputs
   // EntryIndicator
   if (EntryIndicator < 1 || EntryIndicator > 3)             return(catch("onInit(1)  invalid input parameter EntryIndicator: "+ EntryIndicator +" (must be from 1-3)", ERR_INVALID_INPUT_PARAMETER));
   // IndicatorTimeframe
   if (IsTesting() && IndicatorTimeFrame!=Period())          return(catch("onInit(2)  illegal test on "+ PeriodDescription(Period()) +" for configured EA timeframe "+ PeriodDescription(IndicatorTimeFrame), ERR_RUNTIME_ERROR));
   // BreakoutReversal
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL);
   if (LT(BreakoutReversal*Pip, stopLevel*Point))            return(catch("onInit(3)  invalid input parameter BreakoutReversal: "+ NumberToStr(BreakoutReversal, ".1+") +" (must be larger than MODE_STOPLEVEL)", ERR_INVALID_INPUT_PARAMETER));
   double minLots=MarketInfo(Symbol(), MODE_MINLOT), maxLots=MarketInfo(Symbol(), MODE_MAXLOT);
   if (MoneyManagement) {
      // Risk
      if (LE(Risk, 0))                                       return(catch("onInit(4)  invalid input parameter Risk: "+ NumberToStr(Risk, ".1+") +" (must be positive)", ERR_INVALID_INPUT_PARAMETER));
      double lots = CalculateLots(false); if (IsLastError()) return(last_error);
      if (LT(lots, minLots))                                 return(catch("onInit(5)  not enough money ("+ DoubleToStr(AccountEquity()-AccountCredit(), 2) +") for input parameter Risk="+ NumberToStr(Risk, ".1+") +" (resulting position size "+ NumberToStr(lots, ".1+") +" smaller than MODE_MINLOT="+ NumberToStr(minLots, ".1+") +")", ERR_NOT_ENOUGH_MONEY));
      if (GT(lots, maxLots))                                 return(catch("onInit(6)  too large input parameter Risk: "+ NumberToStr(Risk, ".1+") +" (resulting position size "+ NumberToStr(lots, ".1+") +" larger than MODE_MAXLOT="+  NumberToStr(maxLots, ".1+") +")", ERR_INVALID_INPUT_PARAMETER));
   }
   else {
      // ManualLotsize
      if (LT(ManualLotsize, minLots))                        return(catch("onInit(7)  too small input parameter ManualLotsize: "+ NumberToStr(ManualLotsize, ".1+") +" (smaller than MODE_MINLOT="+ NumberToStr(minLots, ".1+") +")", ERR_INVALID_INPUT_PARAMETER));
      if (GT(ManualLotsize, maxLots))                        return(catch("onInit(8)  too large input parameter ManualLotsize: "+ NumberToStr(ManualLotsize, ".1+") +" (larger than MODE_MAXLOT="+ NumberToStr(maxLots, ".1+") +")", ERR_INVALID_INPUT_PARAMETER));
   }
   // EA.StopOnProfit / EA.StopOnLoss
   if (EA.StopOnProfit && EA.StopOnLoss) {
      if (EA.StopOnProfit <= EA.StopOnLoss)                  return(catch("onInit(9)  input parameter mis-match EA.StopOnProfit="+ DoubleToStr(EA.StopOnProfit, 2) +" / EA.StopOnLoss="+ DoubleToStr(EA.StopOnLoss, 2) +" (profit must be larger than loss)", ERR_INVALID_INPUT_PARAMETER));
   }

   // initialize/normalize global vars
   if (UseSpreadMultiplier) { minBarSize = 0;              sMinBarSize = "-";                                }
   else                     { minBarSize = MinBarSize*Pip; sMinBarSize = DoubleToStr(MinBarSize, 1) +" pip"; }
   MaxSpread     = NormalizeDouble(MaxSpread, 1);
   sMaxSpread    = DoubleToStr(MaxSpread, 1);
   orderSlippage = Round(MaxSlippage*Pip/Point);
   orderComment  = "XMT"+ ifString(ChannelBug, "-ChBug", "") + ifString(TakeProfitBug, "-TpBug", "");


   // --- old ---------------------------------------------------------------------------------------------------------------
   if (!Magic) Magic = GenerateMagicNumber();

   if (!ReadOrderLog()) return(last_error);
   SS.All();

   return(catch("onInit(10)"));
}


/**
 * Main function
 *
 * @return int - error status
 */
int onTick() {
   double dNull;
   if (ChannelBug) GetIndicatorValues(dNull, dNull, dNull);    // if the bug is enabled indicators must be tracked every tick
   if (__isChart)  CalculateSpreads();                         // for the visible spread status display

   UpdateOrderStatus();

   if (EA.StopOnProfit || EA.StopOnLoss) {
      if (!CheckTotalTargets()) return(last_error);            // on EA stop that's ERR_CANCELLED_BY_USER
   }

   if (isOpenOrder) {
      if (isOpenPosition) ManageOpenPositions();               // manage open orders
      else                ManagePendingOrders();
   }

   if (!last_error && !isOpenOrder) {
      int signal;
      if (IsEntrySignal(signal)) OpenNewOrder(signal);         // check for and handle entry signals
   }
   return(last_error);
}


/**
 * Track open/closed positions and update statistics.
 *
 * @return bool - success status
 */
bool UpdateOrderStatus() {
   // open order statistics are fully recalculated
   isOpenOrder    = false;                                     // global vars
   isOpenPosition = false;
   openLots       = 0;
   openSwap       = 0;
   openCommission = 0;
   openPl         = 0;
   openPlNet      = 0;

   int orders = ArraySize(orders.ticket);

   // update ticket status
   for (int i=orders-1; i >= 0; i--) {                         // iterate backwards and stop at the first closed ticket
      if (orders.closeTime[i] > 0) break;                      // to increase performance
      isOpenOrder = true;
      if (!SelectTicket(orders.ticket[i], "UpdateOrderStatus(1)")) return(false);

      bool wasPending  = (orders.openType[i] == OP_UNDEFINED); // local vars
      bool isPending   = (OrderType() > OP_SELL);
      bool wasPosition = !wasPending;
      bool isOpen      = !OrderCloseTime();
      bool isClosed    = !isOpen;

      if (wasPending) {
         if (!isPending) {                                     // the pending order was filled
            onPositionOpen(i);
            wasPosition = true;                                // mark as a known open position
         }
         else if (isClosed) {                                  // the pending order was cancelled (externally)
            onOrderDelete(i);
            orders--;
            continue;
         }
      }

      if (wasPosition) {
         orders.swap      [i] = OrderSwap();
         orders.commission[i] = OrderCommission();
         orders.profit    [i] = OrderProfit();

         if (isOpen) {
            isOpenPosition = true;
            openLots       += ifDouble(orders.openType[i]==OP_BUY, orders.lots[i], -orders.lots[i]);
            openSwap       += orders.swap      [i];
            openCommission += orders.commission[i];
            openPl         += orders.profit    [i];
         }
         else /*isClosed*/ {                                   // the open position was closed
            onPositionClose(i);
            isOpenOrder = false;
            closedPositions++;                                 // update closed trade statistics
            closedLots       += orders.lots      [i];
            closedSwap       += orders.swap      [i];
            closedCommission += orders.commission[i];
            closedPl         += orders.profit    [i];
         }
      }
   }

   openPlNet   = openSwap + openCommission + openPl;
   closedPlNet = closedSwap + closedCommission + closedPl;
   totalPlNet  = openPlNet + closedPlNet;

   return(!catch("UpdateOrderStatus(2)"));
}


/**
 * Handle a PositionOpen event. The opened ticket is already selected.
 *
 * @param  int i - ticket index of the opened position
 *
 * @return bool - success status
 */
bool onPositionOpen(int i) {
   // update order log
   orders.openType  [i] = OrderType();
   orders.openTime  [i] = OrderOpenTime();
   orders.openPrice [i] = OrderOpenPrice();
   orders.swap      [i] = OrderSwap();
   orders.commission[i] = OrderCommission();
   orders.profit    [i] = OrderProfit();

   if (IsLogInfo()) {
      // #1 Stop Sell 0.1 GBPUSD at 1.5457'2[ "comment"] was filled[ at 1.5457'2] (market: Bid/Ask[, 0.3 pip [positive ]slippage])
      int    pendingType  = orders.pendingType [i];
      double pendingPrice = orders.pendingPrice[i];

      string sType         = OperationTypeDescription(pendingType);
      string sPendingPrice = NumberToStr(pendingPrice, PriceFormat);
      string sComment      = ""; if (StringLen(OrderComment()) > 0) sComment = " "+ DoubleQuoteStr(OrderComment());
      string message       = "#"+ OrderTicket() +" "+ sType +" "+ NumberToStr(OrderLots(), ".+") +" "+ Symbol() +" at "+ sPendingPrice + sComment +" was filled";

      string sSlippage = "";
      if (NE(OrderOpenPrice(), pendingPrice, Digits)) {
         double slippage = NormalizeDouble((pendingPrice-OrderOpenPrice())/Pip, 1); if (OrderType() == OP_SELL) slippage = -slippage;
            if (slippage > 0) sSlippage = ", "+ DoubleToStr(slippage, Digits & 1) +" pip positive slippage";
            else              sSlippage = ", "+ DoubleToStr(-slippage, Digits & 1) +" pip slippage";
         message = message +" at "+ NumberToStr(OrderOpenPrice(), PriceFormat);
      }
      logInfo("onPositionOpen(1)  "+ message +" (market: "+ NumberToStr(Bid, PriceFormat) +"/"+ NumberToStr(Ask, PriceFormat) + sSlippage +")");
   }

   if (IsTesting() && __ExecutionContext[EC.extReporting]) {
      Test_onPositionOpen(__ExecutionContext, OrderTicket(), OrderType(), OrderLots(), OrderSymbol(), OrderOpenTime(), OrderOpenPrice(), OrderStopLoss(), OrderTakeProfit(), OrderCommission(), OrderMagicNumber(), OrderComment());
   }
   return(!catch("onPositionOpen(2)"));
}


/**
 * Handle a PositionClose event. The closed ticket is already selected.
 *
 * @param  int i - ticket index of the closed position
 *
 * @return bool - success status
 */
bool onPositionClose(int i) {
   // update order log
   orders.closeTime [i] = OrderCloseTime();
   orders.closePrice[i] = OrderClosePrice();
   orders.swap      [i] = OrderSwap();
   orders.commission[i] = OrderCommission();
   orders.profit    [i] = OrderProfit();

   if (IsLogInfo()) {
      // #1 Sell 0.1 GBPUSD at 1.5457'2[ "comment"] was closed at 1.5457'2 (market: Bid/Ask[, so: 47.7%/169.20/354.40])
      string sType       = OperationTypeDescription(OrderType());
      string sOpenPrice  = NumberToStr(OrderOpenPrice(), PriceFormat);
      string sClosePrice = NumberToStr(OrderClosePrice(), PriceFormat);
      string sComment    = ""; if (StringLen(OrderComment()) > 0) sComment = " "+ DoubleQuoteStr(OrderComment());
      string message     = "#"+ OrderTicket() +" "+ sType +" "+ NumberToStr(OrderLots(), ".+") +" "+ Symbol() +" at "+ sOpenPrice + sComment +" was closed at "+ sClosePrice;
      logInfo("onPositionClose(1)  "+ message +" (market: "+ NumberToStr(Bid, PriceFormat) +"/"+ NumberToStr(Ask, PriceFormat) +")");
   }

   if (IsTesting() && __ExecutionContext[EC.extReporting]) {
      Test_onPositionClose(__ExecutionContext, OrderTicket(), OrderCloseTime(), OrderClosePrice(), OrderSwap(), OrderProfit());
   }
   return(!catch("onPositionClose(2)"));
}


/**
 * Handle an OrderDelete event. The deleted ticket is already selected.
 *
 * @param  int i - ticket index of the deleted order
 *
 * @return bool - success status
 */
bool onOrderDelete(int i) {
   if (IsLogInfo()) {
      // #1 Stop Sell 0.1 GBPUSD at 1.5457'2[ "comment"] was deleted
      int    pendingType  = orders.pendingType [i];
      double pendingPrice = orders.pendingPrice[i];

      string sType         = OperationTypeDescription(pendingType);
      string sPendingPrice = NumberToStr(pendingPrice, PriceFormat);
      string sComment      = ""; if (StringLen(OrderComment()) > 0) sComment = " "+ DoubleQuoteStr(OrderComment());
      string message       = "#"+ OrderTicket() +" "+ sType +" "+ NumberToStr(OrderLots(), ".+") +" "+ Symbol() +" at "+ sPendingPrice + sComment +" was deleted";
      logInfo("onOrderDelete(3)  "+ message);
   }
   return(Orders.RemoveTicket(orders.ticket[i]));
}


/**
 * Whether the conditions of an entry signal are satisfied.
 *
 * @param  _Out_ int signal - identifier of the detected signal or NULL
 *
 * @return bool
 */
bool IsEntrySignal(int &signal) {
   signal = NULL;
   if (last_error || isOpenOrder) return(false);

   double barSize = iHigh(NULL, IndicatorTimeFrame, 0) - iLow(NULL, IndicatorTimeFrame, 0);
   if (__isChart) sCurrentBarSize = DoubleToStr(barSize/Pip, 1) +" pip";

   if (UseSpreadMultiplier) {
      if (!avgSpread) /*&&*/ if (!CalculateSpreads())         return(false);
      if (currentSpread > MaxSpread || avgSpread > MaxSpread) return(false);
      minBarSize = avgSpread*Pip * SpreadMultiplier; if (__isChart) SS.MinBarSize();
   }

   //if (GE(barSize, minBarSize)) {                            // TODO: move double comparators to DLL (significant impact)
   if (barSize+0.00000001 >= minBarSize) {
      double channelHigh, channelLow, dNull;
      if (!GetIndicatorValues(channelHigh, channelLow, dNull)) return(false);

      if      (Bid < channelLow)    signal  = SIGNAL_LONG;
      else if (Bid > channelHigh)   signal  = SIGNAL_SHORT;
      if (signal && ReverseSignals) signal ^= 3;               // flip long and short bits (3 = 0011)
   }
   return(signal != NULL);
}


/**
 * Open a new order for the specified entry signal.
 *
 * @param  int signal - order entry signal: SIGNAL_LONG|SIGNAL_SHORT
 *
 * @return bool - success status
 */
bool OpenNewOrder(int signal) {
   if (last_error != 0) return(false);

   double lots   = CalculateLots(true); if (!lots) return(false);
   double spread = Ask-Bid, price, takeprofit, stoploss;
   int oe[];

   if (signal == SIGNAL_LONG) {
      price      = Ask + BreakoutReversal*Pip;
      takeprofit = price + TakeProfit*Pip;
      stoploss   = price - spread - StopLoss*Pip;

      if (!BreakoutReversal) OrderSendEx(Symbol(), OP_BUY,     lots, NULL,  orderSlippage, stoploss, takeprofit, orderComment, Magic, NULL, Blue, NULL, oe);
      else                   OrderSendEx(Symbol(), OP_BUYSTOP, lots, price, NULL,          stoploss, takeprofit, orderComment, Magic, NULL, Blue, NULL, oe);
   }
   else if (signal == SIGNAL_SHORT) {
      price      = Bid - BreakoutReversal*Pip;
      takeprofit = price - TakeProfit*Pip;
      stoploss   = price + spread + StopLoss*Pip;

      if (!BreakoutReversal) OrderSendEx(Symbol(), OP_SELL,     lots, NULL,  orderSlippage, stoploss, takeprofit, orderComment, Magic, NULL, Red, NULL, oe);
      else                   OrderSendEx(Symbol(), OP_SELLSTOP, lots, price, NULL,          stoploss, takeprofit, orderComment, Magic, NULL, Red, NULL, oe);
   }
   else return(!catch("OpenNewOrder(1)  invalid parameter signal: "+ signal, ERR_INVALID_PARAMETER));

   if (oe.IsError(oe)) return(false);

   return(Orders.AddTicket(oe.Ticket(oe), oe.Lots(oe), oe.Type(oe), oe.OpenTime(oe), oe.OpenPrice(oe), NULL, NULL, oe.StopLoss(oe), oe.TakeProfit(oe), NULL, NULL, NULL));
}


/**
 * Manage pending orders. There can be at most one pending order.
 *
 * @return bool - success status
 */
bool ManagePendingOrders() {
   if (!isOpenOrder || isOpenPosition) return(true);

   int i = ArraySize(orders.ticket)-1, oe[];
   if (orders.openType[i] != OP_UNDEFINED) return(!catch("ManagePendingOrders(1)  illegal order type "+ OperationTypeToStr(orders.openType[i]) +" of expected pending order #"+ orders.ticket[i], ERR_ILLEGAL_STATE));

   double openprice, stoploss, takeprofit, spread=Ask-Bid, channelMean, dNull;
   if (!GetIndicatorValues(dNull, dNull, channelMean)) return(false);

   switch (orders.pendingType[i]) {
      case OP_BUYSTOP:
         if (GE(Bid, channelMean)) {                                    // delete the order if price reached mid of channel
            if (!OrderDeleteEx(orders.ticket[i], CLR_NONE, NULL, oe)) return(false);
            Orders.RemoveTicket(orders.ticket[i]);
            return(true);
         }
         openprice = Ask + BreakoutReversal*Pip;                        // trail order entry in breakout direction

         if (GE(orders.pendingPrice[i]-openprice, TrailEntryStep*Pip)) {
            stoploss   = openprice - spread - StopLoss*Pip;
            takeprofit = openprice + TakeProfit*Pip;
            if (!OrderModifyEx(orders.ticket[i], openprice, stoploss, takeprofit, NULL, Lime, NULL, oe)) return(false);
         }
         break;

      case OP_SELLSTOP:
         if (LE(Bid, channelMean)) {                                    // delete the order if price reached mid of channel
            if (!OrderDeleteEx(orders.ticket[i], CLR_NONE, NULL, oe)) return(false);
            Orders.RemoveTicket(orders.ticket[i]);
            return(true);
         }
         openprice = Bid - BreakoutReversal*Pip;                        // trail order entry in breakout direction

         if (GE(openprice-orders.pendingPrice[i], TrailEntryStep*Pip)) {
            stoploss   = openprice + spread + StopLoss*Pip;
            takeprofit = openprice - TakeProfit*Pip;
            if (!OrderModifyEx(orders.ticket[i], openprice, stoploss, takeprofit, NULL, Orange, NULL, oe)) return(false);
         }
         break;

      default:
         return(!catch("ManagePendingOrders(2)  illegal order type "+ OperationTypeToStr(orders.pendingType[i]) +" of expected pending order #"+ orders.ticket[i], ERR_ILLEGAL_STATE));
   }

   if (stoploss > 0) {
      orders.pendingPrice[i] = NormalizeDouble(openprice, Digits);
      orders.stopLoss    [i] = NormalizeDouble(stoploss, Digits);
      orders.takeProfit  [i] = NormalizeDouble(takeprofit, Digits);
   }
   return(true);
}


/**
 * Manage open positions. There can be at most one open position.
 *
 * @return bool - success status
 */
bool ManageOpenPositions() {
   if (!isOpenPosition) return(true);

   int i = ArraySize(orders.ticket)-1, oe[];
   double stoploss, takeprofit;

   switch (orders.openType[i]) {
      case OP_BUY:
         if      (TakeProfitBug)                                   takeprofit = Ask + TakeProfit*Pip;    // erroneous TP calculation
         else if (GE(Bid-orders.openPrice[i], TrailExitStart*Pip)) takeprofit = Bid + TakeProfit*Pip;    // correct TP calculation, also check trail-start
         else                                                      takeprofit = INT_MIN;

         if (GE(takeprofit-orders.takeProfit[i], TrailExitStep*Pip)) {
            stoploss = Bid - StopLoss*Pip;
            if (!OrderModifyEx(orders.ticket[i], NULL, stoploss, takeprofit, NULL, Lime, NULL, oe)) return(false);
         }
         break;

      case OP_SELL:
         if      (TakeProfitBug)                                   takeprofit = Bid - TakeProfit*Pip;    // erroneous TP calculation
         else if (GE(orders.openPrice[i]-Ask, TrailExitStart*Pip)) takeprofit = Ask - TakeProfit*Pip;    // correct TP calculation, also check trail-start
         else                                                      takeprofit = INT_MAX;

         if (GE(orders.takeProfit[i]-takeprofit, TrailExitStep*Pip)) {
            stoploss = Ask + StopLoss*Pip;
            if (!OrderModifyEx(orders.ticket[i], NULL, stoploss, takeprofit, NULL, Orange, NULL, oe)) return(false);
         }
         break;

      default:
         return(!catch("ManageOpenPositions(1)  illegal order type "+ OperationTypeToStr(orders.openType[i]) +" of expected open position #"+ orders.ticket[i], ERR_ILLEGAL_STATE));
   }

   if (stoploss > 0) {
      orders.stopLoss  [i] = NormalizeDouble(stoploss, Digits);
      orders.takeProfit[i] = NormalizeDouble(takeprofit, Digits);
   }
   return(true);
}


/**
 * Check total profit targets and stop the EA if targets have been reached.
 *
 * @return bool - whether the EA shall continue trading, i.e. FALSE on EA stop or in case of errors
 */
bool CheckTotalTargets() {
   bool stopEA = false;

   if (EA.StopOnProfit != 0) stopEA = stopEA || GE(totalPlNet, EA.StopOnProfit);
   if (EA.StopOnLoss   != 0) stopEA = stopEA || LE(totalPlNet, EA.StopOnProfit);

   if (stopEA) {
      if (!CloseOpenOrders())
         return(false);
      return(!SetLastError(ERR_CANCELLED_BY_USER));
   }
   return(true);
}


/**
 * Close all open orders.
 *
 * @return bool - success status
 */
bool CloseOpenOrders() {
   return(!catch("CloseOpenOrders(1)", ERR_NOT_IMPLEMENTED));
}


/**
 * Calculate current and average spread. Online at least 30 ticks are collected before calculating an average.
 *
 * @return bool - success status; FALSE if the average is not yet available
 */
bool CalculateSpreads() {
   static int lastTick; if (Tick == lastTick) {
      return(true);
   }
   lastTick      = Tick;
   currentSpread = NormalizeDouble((Ask-Bid)/Pip, 1);

   if (IsTesting()) {
      avgSpread = currentSpread; if (__isChart) SS.Spreads();
      return(true);
   }

   double spreads[30];
   ArrayCopy(spreads, spreads, 0, 1);
   spreads[29] = currentSpread;

   static int ticks = 0;
   if (ticks < 29) {
      ticks++;
      avgSpread = NULL; if (__isChart) SS.Spreads();
      return(false);
   }

   double sum = 0;
   for (int i=0; i < ticks; i++) {
      sum += spreads[i];
   }
   avgSpread = sum/ticks; if (__isChart) SS.Spreads();

   return(true);
}


/**
 * Return the indicator values forming the signal channel.
 *
 * @param  _Out_ double channelHigh - current upper channel band
 * @param  _Out_ double channelLow  - current lower channel band
 * @param  _Out_ double channelMean - current mid channel
 *
 * @return bool - success status
 */
bool GetIndicatorValues(double &channelHigh, double &channelLow, double &channelMean) {
   static double lastHigh, lastLow, lastMean;
   static int lastTick; if (Tick == lastTick) {
      channelHigh = lastHigh;                   // return cached values
      channelLow  = lastLow;
      channelMean = lastMean;
      return(true);
   }
   lastTick = Tick;

   if (EntryIndicator == 1) {
      channelHigh = iMA(Symbol(), IndicatorTimeFrame, IndicatorPeriods, 0, MODE_LWMA, PRICE_HIGH, 0);
      channelLow  = iMA(Symbol(), IndicatorTimeFrame, IndicatorPeriods, 0, MODE_LWMA, PRICE_LOW, 0);
      channelMean = (channelHigh + channelLow)/2;
   }
   else if (EntryIndicator == 2) {
      channelHigh = iBands(Symbol(), IndicatorTimeFrame, IndicatorPeriods, BollingerBands.Deviation, 0, PRICE_OPEN, MODE_UPPER, 0);
      channelLow  = iBands(Symbol(), IndicatorTimeFrame, IndicatorPeriods, BollingerBands.Deviation, 0, PRICE_OPEN, MODE_LOWER, 0);
      channelMean = (channelHigh + channelLow)/2;
   }
   else if (EntryIndicator == 3) {
      channelHigh = iEnvelopes(Symbol(), IndicatorTimeFrame, IndicatorPeriods, MODE_LWMA, 0, PRICE_OPEN, Envelopes.Deviation, MODE_UPPER, 0);
      channelLow  = iEnvelopes(Symbol(), IndicatorTimeFrame, IndicatorPeriods, MODE_LWMA, 0, PRICE_OPEN, Envelopes.Deviation, MODE_LOWER, 0);
      channelMean = (channelHigh + channelLow)/2;
   }
   else return(!catch("GetIndicatorValues(1)  illegal variable EntryIndicator: "+ EntryIndicator, ERR_ILLEGAL_STATE));

   if (ChannelBug) {                            // reproduce Capella's channel calculation bug (for comparison only)
      if (lastHigh && Bid < channelMean) {      // if enabled the function is called every tick
         channelHigh = lastHigh;
         channelLow  = lastLow;                 // return expired band values
      }
   }
   if (__isChart) {
      static string names[4] = {"", "MovingAverage", "BollingerBands", "Envelopes"};
      sIndicator = StringConcatenate(names[EntryIndicator], "    ", NumberToStr(channelMean, PriceFormat), "  �", DoubleToStr((channelHigh-channelLow)/Pip/2, 1) ,"  (", NumberToStr(channelHigh, PriceFormat), "/", NumberToStr(channelLow, PriceFormat) ,")", ifString(ChannelBug, "   ChannelBug=1", ""));
   }

   lastHigh = channelHigh;                      // cache returned values
   lastLow  = channelLow;
   lastMean = channelMean;

   int error = GetLastError();
   if (!error)                      return(true);
   if (error == ERS_HISTORY_UPDATE) return(false);
   return(!catch("GetIndicatorValues(2)", error));
}


/**
 * Generate a new magic number using parts of the current symbol.                         TODO: still contains various bugs
 *
 * @return int
 */
int GenerateMagicNumber() {
   string values = "EURUSDJPYCHFCADAUDNZDGBP";
   string base   = StrLeft(Symbol(), 3);
   string quote  = StringSubstr(Symbol(), 3, 3);

   int basePos  = StringFind(values, base, 0);
   int quotePos = StringFind(values, quote, 0);

   return(INT_MAX - AccountNumber() - basePos - quotePos);
}


/**
 * Calculate the position size to use.
 *
 * @param  bool checkLimits [optional] - whether to check the symbol's lotsize contraints (default: no)
 *
 * @return double - position size or NULL in case of errors
 */
double CalculateLots(bool checkLimits = false) {
   checkLimits = checkLimits!=0;
   static double lots, lastLots;

   if (MoneyManagement) {
      double equity = AccountEquity() - AccountCredit();
      if (LE(equity, 0)) return(!catch("CalculateLots(1)  equity: "+ DoubleToStr(equity, 2), ERR_NOT_ENOUGH_MONEY));

      double riskPerTrade = Risk/100 * equity;                          // risked equity amount per trade
      double riskPerPip   = riskPerTrade/StopLoss;                      // risked equity amount per pip

      lots = NormalizeLots(riskPerPip/PipValue(), NULL, MODE_FLOOR);    // resulting normalized position size
      if (IsEmptyValue(lots)) return(NULL);

      if (checkLimits) {
         double minLots = MarketInfo(Symbol(), MODE_MINLOT);
         if (LT(lots, minLots)) return(!catch("CalculateLots(2)  equity: "+ DoubleToStr(equity, 2) +" (resulting position size smaller than MODE_MINLOT of "+ NumberToStr(minLots, ".1+") +")", ERR_NOT_ENOUGH_MONEY));

         double maxLots = MarketInfo(Symbol(), MODE_MAXLOT);
         if (GT(lots, maxLots)) {
            if (LT(lastLots, maxLots)) logNotice("CalculateLots(3)  limiting position size to MODE_MAXLOT: "+ NumberToStr(maxLots, ".+") +" lot");
            lots = maxLots;
         }
      }
   }
   else {
      lots = ManualLotsize;
   }
   lastLots = lots;

   if (__isChart) SS.UnitSize(lots);
   return(lots);
}


/**
 * Read and store the full order history.
 *
 * @return bool - success status
 */
bool ReadOrderLog() {
   ArrayResize(orders.ticket,       0);
   ArrayResize(orders.lots,         0);
   ArrayResize(orders.pendingType,  0);
   ArrayResize(orders.pendingPrice, 0);
   ArrayResize(orders.openType,     0);
   ArrayResize(orders.openTime,     0);
   ArrayResize(orders.openPrice,    0);
   ArrayResize(orders.closeTime,    0);
   ArrayResize(orders.closePrice,   0);
   ArrayResize(orders.stopLoss,     0);
   ArrayResize(orders.takeProfit,   0);
   ArrayResize(orders.swap,         0);
   ArrayResize(orders.commission,   0);
   ArrayResize(orders.profit,       0);

   isOpenOrder      = false;
   isOpenPosition   = false;
   openLots         = 0;
   openSwap         = 0;
   openCommission   = 0;
   openPl           = 0;
   openPlNet        = 0;
   closedPositions  = 0;
   closedLots       = 0;
   closedSwap       = 0;
   closedCommission = 0;
   closedPl         = 0;
   closedPlNet      = 0;
   totalPlNet       = 0;

   // all closed positions
   int orders = OrdersHistoryTotal();
   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) return(!catch("ReadOrderLog(1)", ifIntOr(GetLastError(), ERR_RUNTIME_ERROR)));
      if (OrderMagicNumber() != Magic) continue;
      if (OrderType() > OP_SELL)       continue;
      if (OrderSymbol() != Symbol())   continue;

      if (!Orders.AddTicket(OrderTicket(), OrderLots(), OrderType(), OrderOpenTime(), OrderOpenPrice(), OrderCloseTime(), OrderClosePrice(), OrderStopLoss(), OrderTakeProfit(), OrderSwap(), OrderCommission(), OrderProfit()))
         return(false);
   }

   // all open orders
   orders = OrdersTotal();
   for (i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) return(!catch("ReadOrderLog(2)", ifIntOr(GetLastError(), ERR_RUNTIME_ERROR)));
      if (OrderMagicNumber() != Magic) continue;
      if (OrderSymbol() != Symbol())   continue;

      if (!Orders.AddTicket(OrderTicket(), OrderLots(), OrderType(), OrderOpenTime(), OrderOpenPrice(), NULL, NULL, OrderStopLoss(), OrderTakeProfit(), OrderSwap(), OrderCommission(), OrderProfit()))
         return(false);
   }
   return(!catch("ReadOrderLog(3)"));
}


/**
 * Add a new record to the order log and update statistics.
 *
 * @param  int      ticket
 * @param  double   lots
 * @param  int      type
 * @param  datetime openTime
 * @param  double   openPrice
 * @param  datetime closeTime
 * @param  double   closePrice
 * @param  double   stopLoss
 * @param  double   takeProfit
 * @param  double   swap
 * @param  double   commission
 * @param  double   profit
 *
 * @return bool - success status
 */
bool Orders.AddTicket(int ticket, double lots, int type, datetime openTime, double openPrice, datetime closeTime, double closePrice, double stopLoss, double takeProfit, double swap, double commission, double profit) {
   int pos = SearchIntArray(orders.ticket, ticket);
   if (pos >= 0) return(!catch("Orders.AddTicket(1)  invalid parameter ticket: #"+ ticket +" (ticket exists)", ERR_INVALID_PARAMETER));

   int pendingType, openType;
   double pendingPrice;

   if (IsPendingOrderType(type)) {
      pendingType  = type;
      pendingPrice = openPrice;
      openType     = OP_UNDEFINED;
      openTime     = NULL;
      openPrice    = NULL;
   }
   else {
      pendingType  = OP_UNDEFINED;
      pendingPrice = NULL;
      openType     = type;
   }

   int size=ArraySize(orders.ticket), newSize=size+1;
   ArrayResize(orders.ticket,       newSize); orders.ticket      [size] = ticket;
   ArrayResize(orders.lots,         newSize); orders.lots        [size] = lots;
   ArrayResize(orders.pendingType,  newSize); orders.pendingType [size] = pendingType;
   ArrayResize(orders.pendingPrice, newSize); orders.pendingPrice[size] = NormalizeDouble(pendingPrice, Digits);
   ArrayResize(orders.openType,     newSize); orders.openType    [size] = openType;
   ArrayResize(orders.openTime,     newSize); orders.openTime    [size] = openTime;
   ArrayResize(orders.openPrice,    newSize); orders.openPrice   [size] = NormalizeDouble(openPrice, Digits);
   ArrayResize(orders.closeTime,    newSize); orders.closeTime   [size] = closeTime;
   ArrayResize(orders.closePrice,   newSize); orders.closePrice  [size] = NormalizeDouble(closePrice, Digits);
   ArrayResize(orders.stopLoss,     newSize); orders.stopLoss    [size] = NormalizeDouble(stopLoss, Digits);
   ArrayResize(orders.takeProfit,   newSize); orders.takeProfit  [size] = NormalizeDouble(takeProfit, Digits);
   ArrayResize(orders.swap,         newSize); orders.swap        [size] = swap;
   ArrayResize(orders.commission,   newSize); orders.commission  [size] = commission;
   ArrayResize(orders.profit,       newSize); orders.profit      [size] = profit;

   bool _isOpenOrder      = (!closeTime);                                  // local vars
   bool _isPosition       = (openType != OP_UNDEFINED);
   bool _isOpenPosition   = (_isPosition && !closeTime);
   bool _isClosedPosition = (_isPosition && closeTime);

   if (_isOpenOrder) {
      if (isOpenOrder)    return(!catch("Orders.AddTicket(2)  cannot add open order #"+ ticket +" (another open order exists)", ERR_ILLEGAL_STATE));
      isOpenOrder = true;                                                  // global vars
   }
   if (_isOpenPosition) {
      if (isOpenPosition) return(!catch("Orders.AddTicket(3)  cannot add open position #"+ ticket +" (another open position exists)", ERR_ILLEGAL_STATE));
      isOpenPosition = true;
      openLots       += ifDouble(IsLongOrderType(type), lots, -lots);
      openSwap       += swap;
      openCommission += commission;
      openPl         += profit;
      openPlNet       = openSwap + openCommission + openPl;
   }
   if (_isClosedPosition) {
      closedPositions++;
      closedLots       += lots;
      closedSwap       += swap;
      closedCommission += commission;
      closedPl         += profit;
      closedPlNet       = closedSwap + closedCommission + closedPl;
   }
   if (_isPosition) {
      totalPlNet = openPlNet + closedPlNet;
   }
   return(!catch("Orders.AddTicket(4)"));
}


/**
 * Remove a record from the order log.
 *
 * @param  int ticket - ticket of the record
 *
 * @return bool - success status
 */
bool Orders.RemoveTicket(int ticket) {
   int pos = SearchIntArray(orders.ticket, ticket);
   if (pos < 0)                              return(!catch("Orders.RemoveTicket(1)  invalid parameter ticket: #"+ ticket +" (not found)", ERR_INVALID_PARAMETER));
   if (orders.openType[pos] != OP_UNDEFINED) return(!catch("Orders.RemoveTicket(2)  cannot remove an opened position: #"+ ticket, ERR_ILLEGAL_STATE));
   if (!isOpenOrder)                         return(!catch("Orders.RemoveTicket(3)  isOpenOrder is FALSE", ERR_ILLEGAL_STATE));

   isOpenOrder = false;

   ArraySpliceInts   (orders.ticket,       pos, 1);
   ArraySpliceDoubles(orders.lots,         pos, 1);
   ArraySpliceInts   (orders.pendingType,  pos, 1);
   ArraySpliceDoubles(orders.pendingPrice, pos, 1);
   ArraySpliceInts   (orders.openType,     pos, 1);
   ArraySpliceInts   (orders.openTime,     pos, 1);
   ArraySpliceDoubles(orders.openPrice,    pos, 1);
   ArraySpliceInts   (orders.closeTime,    pos, 1);
   ArraySpliceDoubles(orders.closePrice,   pos, 1);
   ArraySpliceDoubles(orders.stopLoss,     pos, 1);
   ArraySpliceDoubles(orders.takeProfit,   pos, 1);
   ArraySpliceDoubles(orders.swap,         pos, 1);
   ArraySpliceDoubles(orders.commission,   pos, 1);
   ArraySpliceDoubles(orders.profit,       pos, 1);

   return(!catch("Orders.RemoveTicket(4)"));
}


/**
 * Display the current runtime status.
 *
 * @param  int error [optional] - error to display (default: none)
 *
 * @return int - the same error or the current error status if no error was passed
 */
int ShowStatus(int error = NO_ERROR) {
   if (!__isChart) return(error);

   string sError = "";
   if      (__STATUS_INVALID_INPUT) sError = StringConcatenate("  [",                 ErrorDescription(ERR_INVALID_INPUT_PARAMETER), "]");
   else if (__STATUS_OFF          ) sError = StringConcatenate("  [switched off => ", ErrorDescription(__STATUS_OFF.reason),         "]");

   string sSpreadInfo = "";
   if (currentSpread+0.00000001 > MaxSpread || avgSpread+0.00000001 > MaxSpread)
      sSpreadInfo = StringConcatenate("  =>  larger then MaxSpread of ", sMaxSpread);

   string msg = StringConcatenate(ProgramName(), "         ", sError,                                                                              NL,
                                                                                                                                                   NL,
                                  "BarSize:    ", sCurrentBarSize, "    MinBarSize: ", sMinBarSize,                                                NL,
                                  "Channel:   ",  sIndicator,                                                                                      NL,
                                  "Spread:    ",  sCurrentSpread, "    Avg: ", sAvgSpread, sSpreadInfo,                                            NL,
                                  "Unitsize:   ", sUnitSize,                                                                                       NL,
                                                                                                                                                   NL,
                                  "Open:      ", NumberToStr(openLots, "+.+"),   " lot                           PL: ", DoubleToStr(openPlNet, 2), NL,
                                  "Closed:    ", closedPositions, " trades    ", NumberToStr(closedLots, ".+"), " lot    PL: ", DoubleToStr(closedPl, 2), "    Commission: ", DoubleToStr(closedCommission, 2), "    Swap: ", DoubleToStr(closedSwap, 2), NL,
                                                                                                                                                   NL,
                                  "Total PL:  ", DoubleToStr(totalPlNet, 2),                                                                       NL
   );

   // 3 lines margin-top for potential indicator legends
   Comment(NL, NL, NL, msg);
   if (__CoreFunction == CF_INIT) WindowRedraw();

   if (!catch("ShowStatus(1)"))
      return(error);
   return(last_error);
}


/**
 * ShowStatus: Update all string representations.
 */
void SS.All() {
   if (__isChart) {
      SS.MinBarSize();
      SS.Spreads();
      SS.UnitSize();
   }
}


/**
 * ShowStatus: Update the string representation of the min. bar size.
 */
void SS.MinBarSize() {
   if (__isChart) {
      sMinBarSize = DoubleToStr(RoundCeil(minBarSize/Pip, 1), 1) +" pip";
   }
}


/**
 * ShowStatus: Update the string representations of current and average spreads.
 */
void SS.Spreads() {
   if (__isChart) {
      sCurrentSpread = DoubleToStr(currentSpread, 1);

      if (IsTesting())     sAvgSpread = sCurrentSpread;
      else if (!avgSpread) sAvgSpread = "-";
      else                 sAvgSpread = DoubleToStr(avgSpread, 2);
   }
}


/**
 * ShowStatus: Update the string representation of the currently used lotsize.
 *
 * @param  double size [optional]
 */
void SS.UnitSize(double size = NULL) {
   if (__isChart) {
      static double lastSize = -1;

      if (size != lastSize) {
         if (!size) sUnitSize = "-";
         else       sUnitSize = NumberToStr(size, ".+") +" lot";
         lastSize = size;
      }
   }
}
