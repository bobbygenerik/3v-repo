package com.example.threevchat.ui.Navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.example.threevchat.ui.screens.HomeScreen
import com.example.threevchat.ui.screens.ProfileScreen
import com.example.threevchat.ui.screens.CallLogsScreen
import com.example.threevchat.ui.screens.SettingsScreen
import com.example.threevchat.viewmodel.MainViewModel
import com.google.firebase.auth.FirebaseAuth

@Composable
fun AppNav(vm: MainViewModel) {
    val navController = rememberNavController()
    val auth = FirebaseAuth.getInstance()
    val currentUser = auth.currentUser
    
    // Get user info from Firebase Auth
    val userId = currentUser?.uid ?: ""
    val displayName = currentUser?.displayName 
        ?: currentUser?.email?.substringBefore('@')
        ?: currentUser?.phoneNumber
        ?: "User"
    val profileUrl = currentUser?.photoUrl?.toString()
    
    NavHost(
        navController = navController,
        startDestination = "home"
    ) {
        composable("home") {
            HomeScreen(
                displayName = displayName,
                profileUrl = profileUrl,
                onOpenProfile = { navController.navigate("profile") },
                onOpenSettings = { navController.navigate("settings") },
                onSignOut = { 
                    vm.signOut()
                    // MainActivity will handle showing sign-in screen
                },
                onViewCallLogs = { navController.navigate("callLogs") },
                vm = vm
            )
        }
        
        composable("profile") {
            ProfileScreen(
                vm = vm,
                onBack = { navController.popBackStack() }
            )
        }
        
        composable("callLogs") {
            CallLogsScreen(
                vm = vm,
                userId = userId
            )
        }
        
        composable("settings") {
            SettingsScreen(
                onBack = { navController.popBackStack() }
            )
        }
    }
}