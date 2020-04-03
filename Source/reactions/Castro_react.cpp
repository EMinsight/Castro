
#include "Castro.H"
#include "Castro_F.H"

#include "AMReX_DistributionMapping.H"

using std::string;
using namespace amrex;

bool
Castro::strang_react_first_half(Real time, Real dt)
{
    BL_PROFILE("Castro::strang_react_first_half()");

    // Sanity check: should only be in here if we're doing CTU or MOL.

    if (time_integration_method != CornerTransportUpwind) {
        amrex::Error("Strang reactions are only supported for the CTU and MOL advance.");
    }

    bool burn_success = true;

    // Get the reactions MultiFab to fill in.

    MultiFab& reactions = get_old_data(Reactions_Type);

    // Ensure we always have valid data, even if we don't do the burn.

    reactions.setVal(0.0);

    if (do_react != 1) return burn_success;

    // Get the current state data.

    MultiFab& state_burn = Sborder;

    // Check if we have any zones to burn.

    if (!valid_zones_to_burn(state_burn)) return burn_success;

    const int ng = state_burn.nGrow();

    // Reactions are expensive and we would usually rather do a
    // communication step than burn on the ghost zones. So what we
    // will do here is create a mask that indicates that we want to
    // turn on the valid interior zones but NOT on the ghost zones
    // that are interior to the level. However, we DO want to burn on
    // the ghost zones that are on the coarse-fine interfaces, since
    // that is going to be more accurate than interpolating from
    // coarse zones. So we will not mask out those zones, and the
    // subsequent FillBoundary call will not interfere with it.

    iMultiFab& interior_mask = build_interior_boundary_mask(ng);

    // The reaction weightings.

    MultiFab* weights;

    // If we're using the custom knapsack weighting, copy state data
    // to a new MultiFab with a corresponding distribution map.

    MultiFab* state_temp;
    MultiFab* reactions_temp;
    iMultiFab* mask_temp;
    MultiFab* weights_temp;

    // Use managed arrays so that we don't have to worry about
    // deleting things at the end.

    Vector<std::unique_ptr<MultiFab> > temp_data;
    std::unique_ptr<iMultiFab> temp_idata;

    if (use_custom_knapsack_weights) {

        weights = &get_old_data(Knapsack_Weight_Type);

        // Note that we want to use the "old" data here; we've already
        // done a swap on the new data for the old data, so this is
        // really the new-time burn from the last timestep.

        const DistributionMapping& dm = DistributionMapping::makeKnapSack(get_old_data(Knapsack_Weight_Type));
        
        temp_data.push_back(std::unique_ptr<MultiFab>(
                                state_temp = new MultiFab(state_burn.boxArray(), dm, state_burn.nComp(), state_burn.nGrow())));
        temp_data.push_back(std::unique_ptr<MultiFab>(
                                reactions_temp = new MultiFab(reactions.boxArray(), dm, reactions.nComp(), reactions.nGrow())));
        temp_data.push_back(std::unique_ptr<MultiFab>(
                                weights_temp = new MultiFab(weights->boxArray(), dm, weights->nComp(), weights->nGrow())));
        temp_idata.reset(mask_temp = new iMultiFab(interior_mask.boxArray(), dm, interior_mask.nComp(), interior_mask.nGrow()));

        // Copy data from the state_burn. Note that this is a parallel copy
        // from FabArray, and the parallel copy assumes that the data
        // on the ghost zones in state_burn is valid and consistent with
        // the data on the interior zones, since either the ghost or
        // valid zones may end up filling a given destination zone.

        state_temp->copy(state_burn, 0, 0, state_burn.nComp(), state_burn.nGrow(), state_burn.nGrow());

        // Create the mask. We cannot use the interior_mask from above, generated by
        // Castro::build_interior_boundary_mask, because we need it to exist on the
        // current DistributionMap and a parallel copy won't work for the mask.

        int ghost_covered_by_valid = 0;
        int other_cells = 1; // uncovered ghost, valid, and outside domain cells are set to 1

        mask_temp->BuildMask(geom.Domain(), geom.periodicity(),
                             ghost_covered_by_valid, other_cells, other_cells, other_cells);

    }
    else {

        state_temp = &state_burn;
        reactions_temp = &reactions;
        mask_temp = &interior_mask;

        // Create a dummy weight array to pass to Fortran.

        temp_data.push_back(std::unique_ptr<MultiFab>(
                                weights_temp = new MultiFab(reactions.boxArray(), reactions.DistributionMap(),
                                                            reactions.nComp(), reactions.nGrow())));

    }

    if (verbose)
        amrex::Print() << "... Entering burner and doing half-timestep of burning." << std::endl << std::endl;

    burn_success = react_state(*state_temp, *reactions_temp, *mask_temp, *weights_temp, time, dt, 1, ng);

    if (verbose)
        amrex::Print() << "... Leaving burner after completing half-timestep of burning." << std::endl << std::endl;

    // Note that this FillBoundary *must* occur before we copy any data back
    // to the main state data; it is the only way to ensure that the parallel
    // copy to follow is sensible, because when we're working with ghost zones
    // the valid and ghost zones must be consistent for the parallel copy.

    state_temp->FillBoundary(geom.periodicity());

    // Copy data back to the state data if necessary.

    if (use_custom_knapsack_weights) {

        state_burn.copy(*state_temp, 0, 0, state_temp->nComp(), state_temp->nGrow(), state_temp->nGrow());
        reactions.copy(*reactions_temp, 0, 0, reactions_temp->nComp(), reactions_temp->nGrow(), reactions_temp->nGrow());
        weights->copy(*weights_temp, 0, 0, weights_temp->nComp(), weights_temp->nGrow(), weights_temp->nGrow());

    }

    // Ensure consistency in internal energy and recompute temperature.

    clean_state(state_burn, time, state_burn.nGrow());

    if (burn_success)
        return true;
    else
        return false;

}



bool
Castro::strang_react_second_half(Real time, Real dt)
{
    BL_PROFILE("Castro::strang_react_second_half()");

    // Sanity check: should only be in here if we're doing CTU or MOL.

    if (time_integration_method != CornerTransportUpwind) {
        amrex::Error("Strang reactions are only supported for the CTU and MOL advance.");
    }

    bool burn_success = true;

    MultiFab& reactions = get_new_data(Reactions_Type);

    // Ensure we always have valid data, even if we don't do the burn.

    reactions.setVal(0.0);

    if (Knapsack_Weight_Type > 0)
        get_new_data(Knapsack_Weight_Type).setVal(1.0);

    if (do_react != 1) return burn_success;

    MultiFab& state_burn = get_new_data(State_Type);

    // Check if we have any zones to burn.

    if (!valid_zones_to_burn(state_burn)) return burn_success;

    // To be consistent with other source term types,
    // we are only applying this on the interior zones.

    const int ng = 0;

    iMultiFab& interior_mask = build_interior_boundary_mask(ng);

    MultiFab* weights;

    // Most of the following uses the same logic as strang_react_first_half;
    // look there for explanatory comments.

    MultiFab* state_temp;
    MultiFab* reactions_temp;
    iMultiFab* mask_temp;
    MultiFab* weights_temp;

    Vector<std::unique_ptr<MultiFab> > temp_data;
    std::unique_ptr<iMultiFab> temp_idata;

    if (use_custom_knapsack_weights) {

        weights = &get_new_data(Knapsack_Weight_Type);

        // Here we use the old-time weights filled in during the first-half Strang-split burn.

        const DistributionMapping& dm = DistributionMapping::makeKnapSack(get_old_data(Knapsack_Weight_Type));

        temp_data.push_back(std::unique_ptr<MultiFab>(
                                state_temp = new MultiFab(state_burn.boxArray(), dm, state_burn.nComp(), state_burn.nGrow())));
        temp_data.push_back(std::unique_ptr<MultiFab>(
                                reactions_temp = new MultiFab(reactions.boxArray(), dm, reactions.nComp(), reactions.nGrow())));
        temp_data.push_back(std::unique_ptr<MultiFab>(
                                weights_temp = new MultiFab(weights->boxArray(), dm, weights->nComp(), weights->nGrow())));
        temp_idata.reset(mask_temp = new iMultiFab(interior_mask.boxArray(), dm, interior_mask.nComp(), interior_mask.nGrow()));

        state_temp->copy(state_burn, 0, 0, state_burn.nComp(), state_burn.nGrow(), state_burn.nGrow());

        int ghost_covered_by_valid = 0;
        int other_cells = 1;

        mask_temp->BuildMask(geom.Domain(), geom.periodicity(),
                             ghost_covered_by_valid, other_cells, other_cells, other_cells);

    }
    else {

        state_temp = &state_burn;
        reactions_temp = &reactions;
        mask_temp = &interior_mask;

        temp_data.push_back(std::unique_ptr<MultiFab>(
                                weights_temp = new MultiFab(reactions.boxArray(), reactions.DistributionMap(),
                                                            reactions.nComp(), reactions.nGrow())));

    }

    if (verbose)
        amrex::Print() << "... Entering burner and doing half-timestep of burning." << std::endl << std::endl;

    burn_success = react_state(*state_temp, *reactions_temp, *mask_temp, *weights_temp, time, dt, 2, ng);

    if (verbose)
        amrex::Print() << "... Leaving burner after completing half-timestep of burning." << std::endl << std::endl;

    state_temp->FillBoundary(geom.periodicity());

    if (use_custom_knapsack_weights) {

        state_burn.copy(*state_temp, 0, 0, state_temp->nComp(), state_temp->nGrow(), state_temp->nGrow());
        reactions.copy(*reactions_temp, 0, 0, reactions_temp->nComp(), reactions_temp->nGrow(), reactions_temp->nGrow());
        weights->copy(*weights_temp, 0, 0, weights_temp->nComp(), weights_temp->nGrow(), weights_temp->nGrow());

    }

    clean_state(state_burn, time + 0.5 * dt, state_burn.nGrow());

    return burn_success;

}



bool
Castro::react_state(MultiFab& s, MultiFab& r, const iMultiFab& m, MultiFab& w, Real time, Real dt_react, int strang_half, int ngrow)
{

    BL_PROFILE("Castro::react_state()");

    // Sanity check: should only be in here if we're doing CTU or MOL.

    if (time_integration_method != CornerTransportUpwind) {
        amrex::Error("Strang reactions are only supported for the CTU and MOL advance.");
    }

    const Real strt_time = ParallelDescriptor::second();

    // Initialize the weights to the default value (everything is weighted equally).

    w.setVal(1.0);

    // Start off assuming a successful burn.

    int burn_success = 1;
    Real burn_failed = 0.0;

#ifdef _OPENMP
#pragma omp parallel reduction(+:burn_failed)
#endif
    for (MFIter mfi(s, TilingIfNotGPU()); mfi.isValid(); ++mfi)
    {

        const Box& bx = mfi.growntilebox(ngrow);

        auto U = s.array(mfi);
        auto reactions = r.array(mfi);
        auto mask = m.array(mfi);
        auto weights = w.array(mfi);

        Real* burn_failed_d = AMREX_MFITER_REDUCE_SUM(&burn_failed);

        AMREX_PARALLEL_FOR_3D(bx, i, j, k,
        {

            burn_t burn_state;

            // Initialize some data for later.

            bool do_burn = true;
            burn_state.success = true;

            // Don't burn on zones that we are intentionally masking out.

            if (mask(i,j,k) != 1) {
                do_burn = false;
            }

            // Don't burn on zones inside shock regions, if the relevant option is set.

#ifdef SHOCK_VAR
            if (U(i,j,k,USHK) > 0.0_rt && disable_shock_burning == 1) {
                do_burn = false;
            }
#endif

            Real rhoInv = 1.0_rt / U(i,j,k,URHO);

            burn_state.rho = U(i,j,k,URHO);
            burn_state.T   = U(i,j,k,UTEMP);
            burn_state.e   = 0.0_rt; // Energy generated by the burn

            for (int n = 0; n < NumSpec; ++n) {
                burn_state.xn[n] = U(i,j,k,UFS+n) * rhoInv;
            }

#if naux > 0
            for (int n = 0; n < NumAux; ++n) {
                burn_state.aux[n] = U(i,j,k,UFX+n) * rhoInv;
            }
#endif

            // Ensure we start with no RHS or Jacobian calls registered.

            burn_state.n_rhs = 0;
            burn_state.n_jac = 0;

            // Don't burn if we're outside of the relevant (rho, T) range.

            if (!okay_to_burn_type(burn_state)) {
                do_burn = false;
            }

            if (do_burn) {
                burner(burn_state, dt_react);
            }

            // If we were unsuccessful, update the failure flag.

            Real failed_tmp = 0.0_rt;

            if (!burn_state.success) {
                failed_tmp = 1.0_rt;
            }

#ifdef AMREX_DEVICE_COMPILE
            Gpu::deviceReduceSum(burn_failed_d, failed_tmp);
#else
            burn_failed_d += failed_temp;
#endif

            if (do_burn) {

                // Note that we want to update the total energy by taking
                // the difference of the old rho*e and the new rho*e. If
                // the user wants to ensure that rho * E = rho * e + rho *
                // K, this reset should be enforced through an appropriate
                // choice for the dual energy formalism parameter
                // dual_energy_eta2 in reset_internal_energy.

                Real delta_e     = burn_state.e;
                Real delta_rho_e = burn_state.rho * delta_e;

                // Add burning rates to reactions MultiFab, but be
                // careful because the reactions and state MFs may
                // not have the same number of ghost cells. Note that
                // we must do this before we actually update the state
                // since we have not saved the old state.

                if (reactions.contains(i,j,k)) {
                    for (int n = 0; n < NumSpec; ++n) {
                        reactions(i,j,k,n) = (burn_state.xn[n] - U(i,j,k,UFS+n) * rhoInv) / dt_react;
                    }
                    reactions(i,j,k,NumSpec  ) = delta_e / dt_react;
                    reactions(i,j,k,NumSpec+1) = delta_rho_e / dt_react;
                }

                U(i,j,k,UEINT) += delta_rho_e;
                U(i,j,k,UEDEN) += delta_rho_e;

                for (int n = 0; n < NumSpec; ++n) {
                    U(i,j,k,UFS+n) = U(i,j,k,URHO) * burn_state.xn[n];
                }

#if naux > 0
                for (int n = 0; n < NumSpec; ++n) {
                    U(i,j,k,UFX+n)  = U(i,j,k,URHO) * burn_state.aux[n];
                }
#endif

                // Insert weights for these burns.

                if (weights.contains(i,j,k)) {
                    weights(i,j,k) = amrex::max(1.0_rt, (Real) (burn_state.n_rhs + 2 * burn_state.n_jac));
                }

            }

        });
        
    }

    if (burn_failed != 0.0) burn_success = 0;

    ParallelDescriptor::ReduceIntMin(burn_success);

    if (print_update_diagnostics) {

        Real e_added = r.sum(NumSpec + 1);

        if (e_added != 0.0)
            amrex::Print() << "... (rho e) added from burning: " << e_added << std::endl << std::endl;

    }

    if (verbose > 0)
    {
        const int IOProc   = ParallelDescriptor::IOProcessorNumber();
        Real      run_time = ParallelDescriptor::second() - strt_time;

#ifdef BL_LAZY
        Lazy::QueueReduction( [=] () mutable {
#endif
        ParallelDescriptor::ReduceRealMax(run_time,IOProc);

        amrex::Print() << "Castro::react_state() time = " << run_time << "\n" << "\n";
#ifdef BL_LAZY
        });
#endif
    }

    if (burn_success)
        return true;
    else
        return false;

}

// Simplified SDC version

bool
Castro::react_state(Real time, Real dt)
{
    BL_PROFILE("Castro::react_state()");

    // Sanity check: should only be in here if we're doing simplified SDC.

    if (time_integration_method != SimplifiedSpectralDeferredCorrections) {
        amrex::Error("This react_state interface is only supported for simplified SDC.");
    }

    const Real strt_time = ParallelDescriptor::second();

    if (verbose)
        amrex::Print() << "... Entering burner and doing full timestep of burning." << std::endl << std::endl;

    MultiFab& S_old = get_old_data(State_Type);
    MultiFab& S_new = get_new_data(State_Type);

    // Build the burning mask, in case the state has ghost zones.

    const int ng = S_new.nGrow();
    const iMultiFab& interior_mask = build_interior_boundary_mask(ng);

    // Create a MultiFab with all of the non-reacting source terms.

    MultiFab A_src(grids, dmap, NUM_STATE, ng);
    sum_of_sources(A_src);

    MultiFab& reactions = get_new_data(Reactions_Type);

    reactions.setVal(0.0);

    // Start off assuming a successful burn.

    int burn_success = 1;
    Real burn_failed = 0.0;

#ifdef _OPENMP
#pragma omp parallel reduction(+:burn_failed)
#endif
    for (MFIter mfi(S_new, TilingIfNotGPU()); mfi.isValid(); ++mfi)
    {

        const Box& bx = mfi.growntilebox(ng);

        FArrayBox& uold    = S_old[mfi];
        FArrayBox& unew    = S_new[mfi];
        FArrayBox& a       = A_src[mfi];
        FArrayBox& r       = reactions[mfi];
        const IArrayBox& m = interior_mask[mfi];

#pragma gpu box(bx)
        ca_react_state_simplified_sdc(AMREX_INT_ANYD(bx.loVect()), AMREX_INT_ANYD(bx.hiVect()),
                                      BL_TO_FORTRAN_ANYD(uold),
                                      BL_TO_FORTRAN_ANYD(unew),
                                      BL_TO_FORTRAN_ANYD(a),
                                      BL_TO_FORTRAN_ANYD(r),
                                      BL_TO_FORTRAN_ANYD(m),
                                      time, dt, sdc_iteration,
                                      AMREX_MFITER_REDUCE_SUM(&burn_failed));

    }

    if (burn_failed != 0.0) burn_success = 0;

    ParallelDescriptor::ReduceIntMin(burn_success);

    if (ng > 0)
        S_new.FillBoundary(geom.periodicity());

    if (print_update_diagnostics) {

        Real e_added = reactions.sum(NumSpec + 1);

        if (e_added != 0.0)
            amrex::Print() << "... (rho e) added from burning: " << e_added << std::endl << std::endl;

    }

    if (verbose) {

        amrex::Print() << "... Leaving burner after completing full timestep of burning." << std::endl << std::endl;

        const int IOProc   = ParallelDescriptor::IOProcessorNumber();
        Real      run_time = ParallelDescriptor::second() - strt_time;

#ifdef BL_LAZY
        Lazy::QueueReduction( [=] () mutable {
#endif
        ParallelDescriptor::ReduceRealMax(run_time, IOProc);

        amrex::Print() << "Castro::react_state() time = " << run_time << std::endl << std::endl;
#ifdef BL_LAZY
        });
#endif

    }

    // For the ca_check_timestep routine, we need to have both the old
    // and new burn defined, so we simply do a copy here
    MultiFab& R_old = get_old_data(Reactions_Type);
    MultiFab& R_new = get_new_data(Reactions_Type);
    MultiFab::Copy(R_new, R_old, 0, 0, R_new.nComp(), R_new.nGrow());


    if (burn_success)
        return true;
    else
        return false;

}



bool
Castro::valid_zones_to_burn(MultiFab& State)
{

    // The default values of the limiters are 0 and 1.e200, respectively.

    Real small = 1.e-10;
    Real large = 1.e199;

    // Check whether we are limiting on either rho or T.

    bool limit_small_rho = react_rho_min >= small;
    bool limit_large_rho = react_rho_max <= large;

    bool limit_rho = limit_small_rho || limit_large_rho;

    bool limit_small_T = react_T_min >= small;
    bool limit_large_T = react_T_max <= large;

    bool limit_T = limit_small_T || limit_large_T;

    bool limit = limit_rho || limit_T;

    if (!limit) return true;

    // Now, if we're limiting on rho, collect the
    // minimum and/or maximum and compare.

    amrex::Vector<Real> small_limiters;
    amrex::Vector<Real> large_limiters;

    bool local = true;

    Real smalldens = small;
    Real largedens = large;

    if (limit_small_rho) {
      smalldens = State.min(URHO, 0, local);
      small_limiters.push_back(smalldens);
    }

    if (limit_large_rho) {
      largedens = State.max(URHO, 0, local);
      large_limiters.push_back(largedens);
    }

    Real small_T = small;
    Real large_T = large;

    if (limit_small_T) {
      small_T = State.min(UTEMP, 0, local);
      small_limiters.push_back(small_T);
    }

    if (limit_large_T) {
      large_T = State.max(UTEMP, 0, local);
      large_limiters.push_back(large_T);
    }

    // Now do the reductions. We're being careful here
    // to limit the amount of work and communication,
    // because regularly doing this check only makes sense
    // if it is negligible compared to the amount of work
    // needed to just do the burn as normal.

    int small_size = small_limiters.size();

    if (small_size > 0) {
        amrex::ParallelDescriptor::ReduceRealMin(small_limiters.dataPtr(), small_size);

        if (limit_small_rho) {
            smalldens = small_limiters[0];
            if (limit_small_T) {
                small_T = small_limiters[1];
            }
        } else {
            small_T = small_limiters[0];
        }
    }

    int large_size = large_limiters.size();

    if (large_size > 0) {
        amrex::ParallelDescriptor::ReduceRealMax(large_limiters.dataPtr(), large_size);

        if (limit_large_rho) {
            largedens = large_limiters[0];
            if (limit_large_T) {
                large_T = large_limiters[1];
            }
        } else {
            large_T = large_limiters[1];
        }
    }

    // Finally check on whether min <= rho <= max
    // and min <= T <= max. The defaults are small
    // and large respectively, so if the limiters
    // are not on, these checks will not be triggered.

    if (largedens >= react_rho_min && smalldens <= react_rho_max &&
        large_T >= react_T_min && small_T <= react_T_max) {
        return true;
    }

    // If we got to this point, we did not survive the limiters,
    // so there are no zones to burn.

    if (verbose > 1)
        amrex::Print() << "  No valid zones to burn, skipping react_state()." << std::endl;

    return false;

}
