extends RefCounted
class_name Achievements
## 里程成就：**每张地图每 500 米算一个**，达成了发奖。
##
## 这里只有纯算术（里程 ↔ 第几个成就 ↔ 奖励），不碰存档、不碰节点，
## 所以可以直接拿数字测。发钱和「已经领过没有」在 [SaveData] 里，
## 飘字在 [HillHud] 里。
##
## **成就是「一个档领一次」的，不是每局一次。** 按局算的话，最优玩法就成了
## 「跑到 500 米就故意翻车，重开，再跑到 500 米」—— 一趟一趟刷，比认真跑下去赚得快。
## 里程纪录也是按档存的（[member SaveData.best_by_map]），成就跟着它走。

## 每隔多少米算一个成就。
const STEP_METERS := 500
## 每个成就发多少金币。
##
## 定 500 是按现有经济来的：一枚金币 25~500（期望值随里程从 62.5 涨到 150，
## 见 [method Pickup.mean_value_at]）、腾空一节 50~200（2.5 秒起，
## 见 [constant HillCar.AIR_BONUS_TIERS]）、独轮一节 75、空翻一圈 300，
## 而一整条升级线点满要 20304、四条全满 81216。
## 500 米（大约 20 秒）给 500，和「翻一整圈」同价 —— 两个都是「干得漂亮」的量级。
##
## 成就是**一个档一辈子领一次**的（见下面的说明），所以它是这几项里唯一
## 会枯竭的收入：一张图跑到 5000 米，这条线就再也发不出钱了。
## 升级的重头戏因此还得是捡金币，成就只是顺路的一笔。
const REWARD := 500


## 里程（米）走到了第几个成就。**没到第一个就是 0**（第 1 个成就叫「1」而不是「0」，
## 这样 0 可以干净地表示「一个都还没拿到」）。
static func index_at(meters: float) -> int:
	return int(floor(maxf(0.0, meters) / float(STEP_METERS)))


## 第 index 个成就对应多少米（index 从 1 开始）。
static func meters_of(index: int) -> int:
	return index * STEP_METERS


## `count` 个成就一共发多少钱。发钱的地方都走这里，免得两处各写一遍乘法各错各的。
static func reward_for(count: int) -> int:
	return maxi(0, count) * REWARD
