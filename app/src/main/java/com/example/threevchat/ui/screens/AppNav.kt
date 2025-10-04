package com.example.threevchat.ui.screens

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.example.threevchat.viewmodel.MainViewModel

sealed class Routes(val route: String) {
    data object Register: Routes("register")
    data object Home: Routes("home")
    data object Call: Routes("call")
    data object CallLogs: Routes("calllogs")
}

@Composable
fun AppNav(vm: MainViewModel) {
    val nav: NavHostController = rememberNavController()
    NavHost(navController = nav, startDestination = Routes.Register.route) {
        composable(Routes.Register.route) {
            RegisterScreen(vm = vm, onRegistered = { nav.navigate(Routes.Home.route) })
        }
        composable(Routes.Home.route) {
            HomeScreen(
                vm = vm,
                onStartCall = { nav.navigate(Routes.Call.route) },
                onViewCallLogs = { nav.navigate(Routes.CallLogs.route) }
            )
        }
        composable(Routes.Call.route) {
            CallScreen(vm = vm)
        }
        composable(Routes.CallLogs.route) {
            val userId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid ?: ""
            CallLogsScreen(vm = vm, userId = userId)
        }
    }
}
