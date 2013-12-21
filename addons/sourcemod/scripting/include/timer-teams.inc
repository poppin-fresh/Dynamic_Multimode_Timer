#if defined _timer_teams_included
 #endinput
#endif
#define _timer_teams_included

forward OnCoopStart(player1,player2);
forward OnCoopConfirm(player1,player2);
forward OnCoopWin(player1,player2);
forward OnCoopForceEnd(player1,player2);
forward OnChallengeStart(client,mate);
forward OnChallengeConfirm(client,mate);
forward OnChallengeWin(winner,loser);
forward OnChallengeForceEnd(winner,loser);

native Timer_GetCoopStatus(client);
native Timer_GetChallengeStatus(client);
