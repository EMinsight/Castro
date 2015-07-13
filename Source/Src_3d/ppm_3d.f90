module ppm_module

  implicit none

  private

  public ppm

contains
  !
  ! characteristics based on u
  !
  subroutine ppm(s,s_l1,s_l2,s_l3,s_h1,s_h2,s_h3, &
                 u,cspd,qd_l1,qd_l2,qd_l3,qd_h1,qd_h2,qd_h3, &
                 flatn,f_l1,f_l2,f_l3,f_h1,f_h2,f_h3, &
                 Ip,Im, &
                 ilo1,ilo2,ihi1,ihi2,dx,dy,dz,dt,k3d,kc, &
                 force_type_in)

    use meth_params_module, only : ppm_type

    implicit none

    integer           s_l1, s_l2, s_l3, s_h1, s_h2, s_h3
    integer          qd_l1,qd_l2,qd_l3,qd_h1,qd_h2,qd_h3
    integer           f_l1, f_l2, f_l3, f_h1, f_h2, f_h3
    integer          ilo1,ilo2,ihi1,ihi2

    double precision     s( s_l1: s_h1, s_l2: s_h2, s_l3: s_h3)
    double precision     u(qd_l1:qd_h1,qd_l2:qd_h2,qd_l3:qd_h3,3)
    double precision  cspd(qd_l1:qd_h1,qd_l2:qd_h2,qd_l3:qd_h3)
    double precision flatn( f_l1: f_h1, f_l2: f_h2, f_l3: f_h3)
    double precision Ip(ilo1-1:ihi1+1,ilo2-1:ihi2+1,1:2,1:3,1:3)
    double precision Im(ilo1-1:ihi1+1,ilo2-1:ihi2+1,1:2,1:3,1:3)

    double precision dx,dy,dz,dt
    integer          k3d,kc
   
    integer, intent(in), optional :: force_type_in

    integer :: ppm_type_to_use

    ppm_type_to_use = ppm_type
    if (present(force_type_in)) ppm_type_to_use = force_type_in

    if (ppm_type_to_use == 1) then

        call ppm_type1(s,s_l1,s_l2,s_l3,s_h1,s_h2,s_h3, &
                       u,cspd,qd_l1,qd_l2,qd_l3,qd_h1,qd_h2,qd_h3, &
                       flatn,f_l1,f_l2,f_l3,f_h1,f_h2,f_h3, &
                       Ip,Im,ilo1,ilo2,ihi1,ihi2,dx,dy,dz,dt,k3d,kc)

    else if (ppm_type_to_use == 2) then

        call ppm_type2(s,s_l1,s_l2,s_l3,s_h1,s_h2,s_h3, &
                       u,cspd,qd_l1,qd_l2,qd_l3,qd_h1,qd_h2,qd_h3, &
                       flatn,f_l1,f_l2,f_l3,f_h1,f_h2,f_h3, &
                       Ip,Im,ilo1,ilo2,ihi1,ihi2,dx,dy,dz,dt,k3d,kc)

    end if

  end subroutine ppm

  ! :::
  ! ::: ----------------------------------------------------------------
  ! :::
  
  subroutine ppm_type1(s,s_l1,s_l2,s_l3,s_h1,s_h2,s_h3, &
                       u,cspd,qd_l1,qd_l2,qd_l3,qd_h1,qd_h2,qd_h3, &
                       flatn,f_l1,f_l2,f_l3,f_h1,f_h2,f_h3, &
                       Ip,Im,ilo1,ilo2,ihi1,ihi2,dx,dy,dz,dt,k3d,kc)

    use mempool_module, only : bl_allocate, bl_deallocate
    use meth_params_module, only : ppm_type, ppm_flatten_before_integrals
    use bl_constants_module
  
    implicit none

    integer           s_l1, s_l2, s_l3, s_h1, s_h2, s_h3
    integer          qd_l1,qd_l2,qd_l3,qd_h1,qd_h2,qd_h3
    integer           f_l1, f_l2, f_l3, f_h1, f_h2, f_h3
    integer          ilo1,ilo2,ihi1,ihi2

    double precision     s( s_l1: s_h1, s_l2: s_h2, s_l3: s_h3)
    double precision     u(qd_l1:qd_h1,qd_l2:qd_h2,qd_l3:qd_h3,3)
    double precision  cspd(qd_l1:qd_h1,qd_l2:qd_h2,qd_l3:qd_h3)
    double precision flatn( f_l1: f_h1, f_l2: f_h2, f_l3: f_h3)

    double precision Ip(ilo1-1:ihi1+1,ilo2-1:ihi2+1,1:2,1:3,1:3)
    double precision Im(ilo1-1:ihi1+1,ilo2-1:ihi2+1,1:2,1:3,1:3)

    double precision dx,dy,dz,dt
    integer          k3d,kc

    ! local
    integer i,j,k

    double precision dtdx, dtdy, dtdz

    double precision dsl, dsr, dsc
    double precision sigma, s6

    ! s_{\ib,+}, s_{\ib,-}
    double precision :: sm, sp

    ! \delta s_{\ib}^{vL}
    double precision, pointer :: dsvl(:,:)
    double precision :: dsvlm, dsvl0, dsvlp

    ! s_{i+\half}^{H.O.}
    double precision, pointer :: sedge(:,:)

    dtdx = dt/dx
    dtdy = dt/dy
    dtdz = dt/dz

    if (ppm_type .ne. 1) &
         call bl_error("Should have ppm_type = 1 in ppm_type1")

    if (s_l1 .gt. ilo1-3 .or. s_l2 .gt. ilo2-3) then
         print *,'Low bounds of array: ',s_l1, s_l2
         print *,'Low bounds of  loop: ',ilo1 , ilo2
         call bl_error("Need more ghost cells on array in ppm_type1")
    end if

    if (s_h1 .lt. ihi1+3 .or. s_h2 .lt. ihi2+3) then
         print *,'Hi  bounds of array: ',s_h1, s_h2
         print *,'Hi  bounds of  loop: ',ihi1 , ihi2
         call bl_error("Need more ghost cells on array in ppm_type1")
    end if

    ! cell-centered indexing w/extra ghost cell
    call bl_allocate(dsvl,ilo1-2,ihi1+2,ilo2-2,ihi2+2)

    ! edge-centered indexing
    call bl_allocate(sedge,ilo1-1,ihi1+2,ilo2-1,ihi2+2)

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! x-direction
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    ! compute s at x-edges

    ! compute van Leer slopes in x-direction
    do j=ilo2-1,ihi2+1
       do i=ilo1-2,ihi1+2
          dsc = HALF * (s(i+1,j,k3d) - s(i-1,j,k3d))
          dsl = TWO  * (s(i  ,j,k3d) - s(i-1,j,k3d))
          dsr = TWO  * (s(i+1,j,k3d) - s(i  ,j,k3d))
          if (dsl*dsr .gt. ZERO) then
             dsvl(i,j) = sign(ONE,dsc)*min(abs(dsc),abs(dsl),abs(dsr))
          else
             dsvl(i,j) = ZERO
          end if
       end do
    end do

    ! interpolate s to x-edges
    do j=ilo2-1,ihi2+1
       do i=ilo1-1,ihi1+2
          sedge(i,j) = HALF*(s(i,j,k3d)+s(i-1,j,k3d)) &
               - SIXTH*(dsvl(i,j)-dsvl(i-1,j))
          ! make sure sedge lies in between adjacent cell-centered values
          sedge(i,j) = max(sedge(i,j),min(s(i,j,k3d),s(i-1,j,k3d)))
          sedge(i,j) = min(sedge(i,j),max(s(i,j,k3d),s(i-1,j,k3d)))
       end do
    end do

    do j=ilo2-1,ihi2+1
       do i=ilo1-1,ihi1+1

          ! copy sedge into sp and sm
          sm = sedge(i  ,j)
          sp = sedge(i+1,j)

          if (ppm_flatten_before_integrals == 1) then
             ! flatten the parabola BEFORE doing the other                     
             ! monotonization -- this is the method that Flash does       
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif

          ! modify using quadratic limiters -- note this version of the limiting comes
          ! from Colella and Sekora (2008), not the original PPM paper.
          if ((sp-s(i,j,k3d))*(s(i,j,k3d)-sm) .le. ZERO) then
             sp = s(i,j,k3d)
             sm = s(i,j,k3d)

          else if (abs(sp-s(i,j,k3d)) .ge. TWO*abs(sm-s(i,j,k3d))) then
          !else if (-(sp-sm)**2/SIX > &
          !     (sp - sm)*(s(i,j,k3d) - HALF*(sm + sp))) then
             sp = THREE*s(i,j,k3d) - TWO*sm

          else if (abs(sm-s(i,j,k3d)) .ge. TWO*abs(sp-s(i,j,k3d))) then
          !else if ((sp-sm)*(s(i,j,k3d) - HALF*(sm + sp)) > &
          !     (sp - sm)**2/SIX) then
             sm = THREE*s(i,j,k3d) - TWO*sp
          end if

          if (ppm_flatten_before_integrals == 2) then
             ! flatten the parabola AFTER doing the monotonization --
             ! this is the method that Miller & Colella do
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif

          ! compute x-component of Ip and Im
          s6 = SIX*s(i,j,k3d) - THREE*(sm+sp)

          ! Ip/m is the integral under the parabola for the extent
          ! that a wave can travel over a timestep
          !
          ! Ip integrates to the right edge of a cell
          ! Im integrates to the left edge of a cell

          ! u-c wave
          sigma = abs(u(i,j,k3d,1)-cspd(i,j,k3d))*dtdx

          if (u(i,j,k3d,1)-cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,1,1) = sp
          else
             Ip(i,j,kc,1,1) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,1)-cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,1,1) = sm 
          else
             Im(i,j,kc,1,1) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! u wave
          sigma = abs(u(i,j,k3d,1))*dtdx

          if (u(i,j,k3d,1) <= ZERO) then
             Ip(i,j,kc,1,2) = sp 
          else
             Ip(i,j,kc,1,2) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif
             
          if (u(i,j,k3d,1) >= ZERO) then
             Im(i,j,kc,1,2) = sm 
          else
             Im(i,j,kc,1,2) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! u+c wave
          sigma = abs(u(i,j,k3d,1)+cspd(i,j,k3d))*dtdx

          if (u(i,j,k3d,1)+cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,1,3) = sp 
          else
             Ip(i,j,kc,1,3) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,1)+cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,1,3) = sm 
          else
             Im(i,j,kc,1,3) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

       end do
    end do

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! y-direction
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    ! compute s at y-edges

    ! compute van Leer slopes in y-direction
    do j=ilo2-2,ihi2+2
       do i=ilo1-1,ihi1+1
          dsc = HALF * (s(i,j+1,k3d) - s(i,j-1,k3d))
          dsl = TWO  * (s(i,j  ,k3d) - s(i,j-1,k3d))
          dsr = TWO  * (s(i,j+1,k3d) - s(i,j  ,k3d))
          if (dsl*dsr .gt. ZERO) then
             dsvl(i,j) = sign(ONE,dsc)*min(abs(dsc),abs(dsl),abs(dsr))
          else
             dsvl(i,j) = ZERO
          end if
       end do
    end do

    ! interpolate s to y-edges
    do j=ilo2-1,ihi2+2
       do i=ilo1-1,ihi1+1
          sedge(i,j) = HALF*(s(i,j,k3d)+s(i,j-1,k3d)) &
               - SIXTH*(dsvl(i,j)-dsvl(i,j-1))
          ! make sure sedge lies in between adjacent cell-centered values
          sedge(i,j) = max(sedge(i,j),min(s(i,j,k3d),s(i,j-1,k3d)))
          sedge(i,j) = min(sedge(i,j),max(s(i,j,k3d),s(i,j-1,k3d)))
       end do
    end do

    do j=ilo2-1,ihi2+1
       do i=ilo1-1,ihi1+1

          ! copy sedge into sp and sm
          sm = sedge(i,j  )
          sp = sedge(i,j+1)

          if (ppm_flatten_before_integrals == 1) then
             ! flatten the parabola BEFORE doing the other                     
             ! monotonization -- this is the method that Flash does       
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif

          ! modify using quadratic limiters
          if ((sp-s(i,j,k3d))*(s(i,j,k3d)-sm) .le. ZERO) then
             sp = s(i,j,k3d)
             sm = s(i,j,k3d)

          else if (abs(sp-s(i,j,k3d)) .ge. TWO*abs(sm-s(i,j,k3d))) then
          !else if (-(sp-sm)**2/SIX > &
          !     (sp - sm)*(s(i,j,k3d) - HALF*(sm + sp))) then
             sp = THREE*s(i,j,k3d) - TWO*sm

          else if (abs(sm-s(i,j,k3d)) .ge. TWO*abs(sp-s(i,j,k3d))) then
          !else if ((sp-sm)*(s(i,j,k3d) - HALF*(sm + sp)) > &
          !     (sp - sm)**2/SIX) then
             sm = THREE*s(i,j,k3d) - TWO*sp
          end if

          if (ppm_flatten_before_integrals == 2) then
             ! flatten the parabola AFTER doing the monotonization --
             ! this is the method that Miller & Colella do
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif

          ! compute y-component of Ip and Im
          s6 = SIX*s(i,j,k3d) - THREE*(sm+sp)

          ! v-c wave
          sigma = abs(u(i,j,k3d,2)-cspd(i,j,k3d))*dtdy

          if (u(i,j,k3d,2)-cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,2,1) = sp
          else
             Ip(i,j,kc,2,1) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,2)-cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,2,1) = sm 
          else
             Im(i,j,kc,2,1) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! v wave
          sigma = abs(u(i,j,k3d,2))*dtdy

          if (u(i,j,k3d,2) <= ZERO) then
             Ip(i,j,kc,2,2) = sp 
          else
             Ip(i,j,kc,2,2) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,2) >= ZERO) then
             Im(i,j,kc,2,2) = sm 
          else
             Im(i,j,kc,2,2) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! v+c wave
          sigma = abs(u(i,j,k3d,2)+cspd(i,j,k3d))*dtdy

          if (u(i,j,k3d,2)+cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,2,3) = sp 
          else
             Ip(i,j,kc,2,3) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,2)+cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,2,3) = sm 
          else
             Im(i,j,kc,2,3) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

       end do
    end do

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! z-direction
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    ! compute s at z-edges

    ! compute van Leer slopes in z-direction

    do j=ilo2-1,ihi2+1
       do i=ilo1-1,ihi1+1

          ! compute on slab below
          k = k3d-1
          dsc = HALF * (s(i,j,k+1) - s(i,j,k-1))
          dsl = TWO  * (s(i,j,k  ) - s(i,j,k-1))
          dsr = TWO  * (s(i,j,k+1) - s(i,j,k  ))
          if (dsl*dsr .gt. ZERO) then
             dsvlm = sign(ONE,dsc)*min(abs(dsc),abs(dsl),abs(dsr))
          else
             dsvlm = ZERO
          end if

          ! compute on slab above
          k = k3d+1
          dsc = HALF * (s(i,j,k+1) - s(i,j,k-1))
          dsl = TWO  * (s(i,j,k  ) - s(i,j,k-1))
          dsr = TWO  * (s(i,j,k+1) - s(i,j,k  ))
          if (dsl*dsr .gt. ZERO) then
             dsvlp = sign(ONE,dsc)*min(abs(dsc),abs(dsl),abs(dsr))
          else
             dsvlp = ZERO
          end if

          ! compute on current slab
          k = k3d
          dsc = HALF * (s(i,j,k+1) - s(i,j,k-1))
          dsl = TWO  * (s(i,j,k  ) - s(i,j,k-1))
          dsr = TWO  * (s(i,j,k+1) - s(i,j,k  ))
          if (dsl*dsr .gt. ZERO) then
             dsvl0 = sign(ONE,dsc)*min(abs(dsc),abs(dsl),abs(dsr))
          else
             dsvl0 = ZERO
          end if

          ! interpolate to lo face
          k = k3d
          sm = HALF*(s(i,j,k)+s(i,j,k-1)) - SIXTH*(dsvl0-dsvlm)
          ! make sure sedge lies in between adjacent cell-centered values
          sm = max(sm,min(s(i,j,k),s(i,j,k-1)))
          sm = min(sm,max(s(i,j,k),s(i,j,k-1)))

          ! interpolate to hi face
          k = k3d+1
          sp = HALF*(s(i,j,k)+s(i,j,k-1)) - SIXTH*(dsvlp-dsvl0)

          ! make sure sedge lies in between adjacent cell-centered values
          sp = max(sp,min(s(i,j,k),s(i,j,k-1)))
          sp = min(sp,max(s(i,j,k),s(i,j,k-1)))

          if (ppm_flatten_before_integrals == 1) then
             ! flatten the parabola BEFORE doing the other                     
             ! monotonization -- this is the method that Flash does       
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif


          ! modify using quadratic limiters
          if ((sp-s(i,j,k3d))*(s(i,j,k3d)-sm) .le. ZERO) then
             sp = s(i,j,k3d)
             sm = s(i,j,k3d)

          else if (abs(sp-s(i,j,k3d)) .ge. TWO*abs(sm-s(i,j,k3d))) then
          !else if (-(sp-sm)**2/SIX > &
          !     (sp - sm)*(s(i,j,k3d) - HALF*(sm + sp))) then
             sp = THREE*s(i,j,k3d) - TWO*sm

          else if (abs(sm-s(i,j,k3d)) .ge. TWO*abs(sp-s(i,j,k3d))) then
          !else if ((sp-sm)*(s(i,j,k3d) - HALF*(sm + sp)) > &
          !     (sp - sm)**2/SIX) then
             sm = THREE*s(i,j,k3d) - TWO*sp
          end if

          if (ppm_flatten_before_integrals == 2) then
             ! flatten the parabola AFTER doing the monotonization --
             ! this is the method that Miller & Colella do
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif

          ! compute z-component of Ip and Im
          s6 = SIX*s(i,j,k3d) - THREE*(sm+sp)

          ! w-c wave
          sigma = abs(u(i,j,k3d,3)-cspd(i,j,k3d))*dtdz

          if (u(i,j,k3d,3)-cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,3,1) = sp 
          else
             Ip(i,j,kc,3,1) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,3)-cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,3,1) = sm 
          else
             Im(i,j,kc,3,1) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! w wave
          sigma = abs(u(i,j,k3d,3))*dtdz

          if (u(i,j,k3d,3) <= ZERO) then
             Ip(i,j,kc,3,2) = sp 
          else
             Ip(i,j,kc,3,2) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,3) >= ZERO) then
             Im(i,j,kc,3,2) = sm 
          else
             Im(i,j,kc,3,2) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! w+c wave
          sigma = abs(u(i,j,k3d,3)+cspd(i,j,k3d))*dtdz

          if (u(i,j,k3d,3)+cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,3,3) = sp 
          else
             Ip(i,j,kc,3,3) = sp - &
               HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,3)+cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,3,3) = sm 
          else
             Im(i,j,kc,3,3) = sm + &
               HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

       end do
    end do

    call bl_deallocate(dsvl)
    call bl_deallocate(sedge)

  end subroutine ppm_type1

  ! :::
  ! ::: ----------------------------------------------------------------
  ! :::

  subroutine ppm_type2(s,s_l1,s_l2,s_l3,s_h1,s_h2,s_h3, &
                       u,cspd,qd_l1,qd_l2,qd_l3,qd_h1,qd_h2,qd_h3, &
                       flatn,f_l1,f_l2,f_l3,f_h1,f_h2,f_h3, &
                       Ip,Im,ilo1,ilo2,ihi1,ihi2,dx,dy,dz,dt,k3d,kc)

    use mempool_module, only : bl_allocate, bl_deallocate
    use meth_params_module, only : ppm_type, ppm_flatten_before_integrals
    use bl_constants_module

    implicit none

    integer           s_l1, s_l2, s_l3, s_h1, s_h2, s_h3
    integer          qd_l1,qd_l2,qd_l3,qd_h1,qd_h2,qd_h3
    integer           f_l1, f_l2, f_l3, f_h1, f_h2, f_h3
    integer          ilo1,ilo2,ihi1,ihi2
    double precision s( s_l1: s_h1, s_l2: s_h2, s_l3: s_h3)
    double precision u(qd_l1:qd_h1,qd_l2:qd_h2,qd_l3:qd_h3,1:3)
    double precision cspd(qd_l1:qd_h1,qd_l2:qd_h2,qd_l3:qd_h3)
    double precision flatn(f_l1:f_h1,f_l2:f_h2,f_l3:f_h3)
    double precision Ip(ilo1-1:ihi1+1,ilo2-1:ihi2+1,1:2,1:3,1:3)
    double precision Im(ilo1-1:ihi1+1,ilo2-1:ihi2+1,1:2,1:3,1:3)
    double precision dx,dy,dz,dt
    integer          k3d,kc

    ! local
    integer i,j,k
    logical extremum, bigp, bigm

    double precision dtdx, dtdy, dtdz

    double precision D2, D2C, D2L, D2R, D2LIM, alphap, alpham
    double precision sgn, sigma, s6
    double precision dafacem, dafacep, dabarm, dabarp, dafacemin, dabarmin
    double precision dachkm, dachkp
    double precision amax, delam, delap

    ! s_{\ib,+}, s_{\ib,-}
    double precision :: sm, sp

    ! s_{i+\half}^{H.O.}
    double precision, pointer :: sedge(:,:)
    double precision, pointer :: sedgez(:,:,:)

    ! constant used in Colella 2008
    double precision, parameter :: C = 1.25d0

    dtdx = dt/dx
    dtdy = dt/dy
    dtdz = dt/dz

    if (ppm_type .ne. 2) &
         call bl_error("Should have ppm_type = 2 in ppm_type2")

    if (s_l1 .gt. ilo1-3 .or. s_l2 .gt. ilo2-3) then
         print *,'Low bounds of array: ',s_l1, s_l2
         print *,'Low bounds of  loop: ',ilo1 , ilo2
         call bl_error("Need more ghost cells on array in ppm_type2")
    end if

    if (s_h1 .lt. ihi1+3 .or. s_h2 .lt. ihi2+3) then
         print *,'Hi  bounds of array: ',s_h1, s_h2
         print *,'Hi  bounds of  loop: ',ihi1 , ihi2
         call bl_error("Need more ghost cells on array in ppm_type2")
    end if

    ! edge-centered indexing
    call bl_allocate(sedge,ilo1-2,ihi1+3,ilo2-2,ihi2+3)
    call bl_allocate(sedgez,ilo1-1,ihi1+1,ilo2-1,ihi2+1,k3d-1,k3d+2)

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! x-direction
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    ! compute s at x-edges

    ! interpolate s to x-edges
    do j=ilo2-1,ihi2+1
       do i=ilo1-2,ihi1+3
          sedge(i,j) = SEVEN12TH*(s(i-1,j,k3d)+s(i  ,j,k3d)) &
               - TWELFTH*(s(i-2,j,k3d)+s(i+1,j,k3d))
          !
          ! limit sedge
          !
          if ((sedge(i,j)-s(i-1,j,k3d))*(s(i,j,k3d)-sedge(i,j)) .lt. ZERO) then
             D2  = THREE*(s(i-1,j,k3d)-TWO*sedge(i,j)+s(i,j,k3d))
             D2L = s(i-2,j,k3d)-TWO*s(i-1,j,k3d)+s(i,j,k3d)
             D2R = s(i-1,j,k3d)-TWO*s(i,j,k3d)+s(i+1,j,k3d)
             sgn = sign(ONE,D2)
             D2LIM = sgn*max(min(C*sgn*D2L,C*sgn*D2R,sgn*D2),ZERO)
             sedge(i,j) = HALF*(s(i-1,j,k3d)+s(i,j,k3d)) - SIXTH*D2LIM
          end if
       end do
    end do
    !
    ! Use Colella 2008 limiters.
    !
    ! This is a new version of the algorithm to eliminate sensitivity to roundoff.
    !
    do j=ilo2-1,ihi2+1
       do i=ilo1-1,ihi1+1

          alphap   = sedge(i+1,j)-s(i,j,k3d)
          alpham   = sedge(i  ,j)-s(i,j,k3d)
          bigp     = abs(alphap).gt.TWO*abs(alpham)
          bigm     = abs(alpham).gt.TWO*abs(alphap)
          extremum = .false.

          if (alpham*alphap .ge. ZERO) then
             extremum = .true.
          else if (bigp .or. bigm) then
             !
             ! Possible extremum. We look at cell centered values and face
             ! centered values for a change in sign in the differences adjacent to
             ! the cell. We use the pair of differences whose minimum magnitude is the
             ! largest, and thus least susceptible to sensitivity to roundoff.
             !
             dafacem   = sedge(i,j) - sedge(i-1,j)
             dafacep   = sedge(i+2,j) - sedge(i+1,j)
             dabarm    = s(i,j,k3d) - s(i-1,j,k3d)
             dabarp    = s(i+1,j,k3d) - s(i,j,k3d)
             dafacemin = min(abs(dafacem),abs(dafacep))
             dabarmin  = min(abs(dabarm),abs(dabarp))
             if (dafacemin.ge.dabarmin) then
                dachkm = dafacem
                dachkp = dafacep
             else
                dachkm = dabarm
                dachkp = dabarp
             endif
             extremum = (dachkm*dachkp .le. ZERO)
          end if

          if (extremum) then
             D2     = SIX*(alpham + alphap)
             D2L    = s(i-2,j,k3d)-TWO*s(i-1,j,k3d)+s(i,j,k3d)
             D2R    = s(i,j,k3d)-TWO*s(i+1,j,k3d)+s(i+2,j,k3d)
             D2C    = s(i-1,j,k3d)-TWO*s(i,j,k3d)+s(i+1,j,k3d)
             sgn    = sign(ONE,D2)
             D2LIM  = max(min(sgn*D2,C*sgn*D2L,C*sgn*D2R,C*sgn*D2C),ZERO)
             alpham = alpham*D2LIM/max(abs(D2),1.d-10)
             alphap = alphap*D2LIM/max(abs(D2),1.d-10)
          else
             if (bigp) then
                sgn   = sign(ONE,alpham)
                amax  = -alphap**2 / (4*(alpham + alphap))
                delam = s(i-1,j,k3d) - s(i,j,k3d)
                if (sgn*amax .ge. sgn*delam) then
                   if (sgn*(delam - alpham).ge.1.d-10) then
                      alphap = (-TWO*delam - TWO*sgn*sqrt(delam**2 - delam*alpham))
                   else 
                      alphap = -TWO*alpham
                   endif
                endif
             end if
             if (bigm) then
                sgn   = sign(ONE,alphap)
                amax  = -alpham**2 / (4*(alpham + alphap))
                delap = s(i+1,j,k3d) - s(i,j,k3d)
                if (sgn*amax .ge. sgn*delap) then
                   if (sgn*(delap - alphap).ge.1.d-10) then
                      alpham = (-TWO*delap - TWO*sgn*sqrt(delap**2 - delap*alphap))
                   else
                      alpham = -TWO*alphap
                   endif
                endif
             end if
          end if

          sm = s(i,j,k3d) + alpham
          sp = s(i,j,k3d) + alphap

          if (ppm_flatten_before_integrals > 0) then
             ! flatten the parabola AFTER doing the monotonization 
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif

          !
          ! Compute x-component of Ip and Im.
          !
          s6    = SIX*s(i,j,k3d) - THREE*(sm+sp)

          ! u-c wave
          sigma = abs(u(i,j,k3d,1)-cspd(i,j,k3d))*dtdx

          if (u(i,j,k3d,1)-cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,1,1) = sp
          else
             Ip(i,j,kc,1,1) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,1)-cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,1,1) = sm
          else
             Im(i,j,kc,1,1) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! u wave
          sigma = abs(u(i,j,k3d,1))*dtdx

          if (u(i,j,k3d,1) <= ZERO) then
             Ip(i,j,kc,1,2) = sp
          else
             Ip(i,j,kc,1,2) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,1) >= ZERO) then
             Im(i,j,kc,1,2) = sm
          else
             Im(i,j,kc,1,2) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! u+c wave
          sigma = abs(u(i,j,k3d,1)+cspd(i,j,k3d))*dtdx

          if (u(i,j,k3d,1)+cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,1,3) = sp 
          else
             Ip(i,j,kc,1,3) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,1)+cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,1,3) = sm 
          else
             Im(i,j,kc,1,3) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

       end do
    end do

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! y-direction
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    ! compute s at y-edges

    ! interpolate s to y-edges
    do j=ilo2-2,ihi2+3
       do i=ilo1-1,ihi1+1
          sedge(i,j) = SEVEN12TH*(s(i,j-1,k3d)+s(i,j,k3d)) &
               - TWELFTH*(s(i,j-2,k3d)+s(i,j+1,k3d))
          !
          ! limit sedge
          !
          if ((sedge(i,j)-s(i,j-1,k3d))*(s(i,j,k3d)-sedge(i,j)) .lt. ZERO) then
             D2  = THREE*(s(i,j-1,k3d)-TWO*sedge(i,j)+s(i,j,k3d))
             D2L = s(i,j-2,k3d)-TWO*s(i,j-1,k3d)+s(i,j,k3d)
             D2R = s(i,j-1,k3d)-TWO*s(i,j,k3d)+s(i,j+1,k3d)
             sgn = sign(ONE,D2)
             D2LIM = sgn*max(min(C*sgn*D2L,C*sgn*D2R,sgn*D2),ZERO)
             sedge(i,j) = HALF*(s(i,j-1,k3d)+s(i,j,k3d)) - SIXTH*D2LIM
          end if
       end do
    end do
    !
    ! Use Colella 2008 limiters.
    !
    ! This is a new version of the algorithm to eliminate sensitivity to roundoff.
    !
    do j=ilo2-1,ihi2+1
       do i=ilo1-1,ihi1+1

          alphap   = sedge(i,j+1)-s(i,j,k3d)
          alpham   = sedge(i,j  )-s(i,j,k3d)
          bigp     = abs(alphap).gt.TWO*abs(alpham)
          bigm     = abs(alpham).gt.TWO*abs(alphap)
          extremum = .false.

          if (alpham*alphap .ge. ZERO) then
             extremum = .true.
          else if (bigp .or. bigm) then
             !
             ! Possible extremum. We look at cell centered values and face
             ! centered values for a change in sign in the differences adjacent to
             ! the cell. We use the pair of differences whose minimum magnitude is the
             ! largest, and thus least susceptible to sensitivity to roundoff.
             !
             dafacem   = sedge(i,j) - sedge(i,j-1)
             dafacep   = sedge(i,j+2) - sedge(i,j+1)
             dabarm    = s(i,j,k3d) - s(i,j-1,k3d)
             dabarp    = s(i,j+1,k3d) - s(i,j,k3d)
             dafacemin = min(abs(dafacem),abs(dafacep))
             dabarmin  = min(abs(dabarm),abs(dabarp))
             if (dafacemin.ge.dabarmin) then
                dachkm = dafacem
                dachkp = dafacep
             else
                dachkm = dabarm
                dachkp = dabarp
             endif
             extremum = (dachkm*dachkp .le. ZERO)
          end if

          if (extremum) then
             D2     = SIX*(alpham + alphap)
             D2L    = s(i,j-2,k3d)-TWO*s(i,j-1,k3d)+s(i,j,k3d)
             D2R    = s(i,j,k3d)-TWO*s(i,j+1,k3d)+s(i,j+2,k3d)
             D2C    = s(i,j-1,k3d)-TWO*s(i,j,k3d)+s(i,j+1,k3d)
             sgn    = sign(ONE,D2)
             D2LIM  = max(min(sgn*D2,C*sgn*D2L,C*sgn*D2R,C*sgn*D2C),ZERO)
             alpham = alpham*D2LIM/max(abs(D2),1.d-10)
             alphap = alphap*D2LIM/max(abs(D2),1.d-10)
          else
             if (bigp) then
                sgn   = sign(ONE,alpham)
                amax  = -alphap**2 / (4*(alpham + alphap))
                delam = s(i,j-1,k3d) - s(i,j,k3d)
                if (sgn*amax .ge. sgn*delam) then
                   if (sgn*(delam - alpham).ge.1.d-10) then
                      alphap = (-TWO*delam - TWO*sgn*sqrt(delam**2 - delam*alpham))
                   else 
                      alphap = -TWO*alpham
                   endif
                endif
             end if
             if (bigm) then
                sgn   = sign(ONE,alphap)
                amax  = -alpham**2 / (4*(alpham + alphap))
                delap = s(i,j+1,k3d) - s(i,j,k3d)
                if (sgn*amax .ge. sgn*delap) then
                   if (sgn*(delap - alphap).ge.1.d-10) then
                      alpham = (-TWO*delap - TWO*sgn*sqrt(delap**2 - delap*alphap))
                   else
                      alpham = -TWO*alphap
                   endif
                endif
             end if
          end if

          sm = s(i,j,k3d) + alpham
          sp = s(i,j,k3d) + alphap

          if (ppm_flatten_before_integrals > 0) then
             ! flatten the parabola AFTER doing the monotonization 
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif


          !
          ! Compute y-component of Ip and Im.
          !
          s6    = SIX*s(i,j,k3d) - THREE*(sm+sp)

          ! v-c wave
          sigma = abs(u(i,j,k3d,2)-cspd(i,j,k3d))*dtdy

          if (u(i,j,k3d,2)-cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,2,1) = sp 
          else
             Ip(i,j,kc,2,1) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,2)-cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,2,1) = sm 
          else
             Im(i,j,kc,2,1) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! v wave
          sigma = abs(u(i,j,k3d,2))*dtdy

          if (u(i,j,k3d,2) <= ZERO) then
             Ip(i,j,kc,2,2) = sp 
          else
             Ip(i,j,kc,2,2) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,2) >= ZERO) then
             Im(i,j,kc,2,2) = sm 
          else
             Im(i,j,kc,2,2) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! v+c wave
          sigma = abs(u(i,j,k3d,2)+cspd(i,j,k3d))*dtdy

          if (u(i,j,k3d,2)+cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,2,3) = sp 
          else
             Ip(i,j,kc,2,3) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,2)+cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,2,3) = sm 
          else
             Im(i,j,kc,2,3) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

       end do
    end do

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! z-direction
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    ! compute s at z-edges

    ! interpolate s to z-edges
    do k=k3d-1,k3d+2
       do j=ilo2-1,ihi2+1
          do i=ilo1-1,ihi1+1
             sedgez(i,j,k) = SEVEN12TH*(s(i,j,k-1)+s(i,j,k)) &
                  - TWELFTH*(s(i,j,k-2)+s(i,j,k+1))
             !
             ! limit sedgez
             !
             if ((sedgez(i,j,k)-s(i,j,k-1))*(s(i,j,k)-sedgez(i,j,k)) .lt. ZERO) then
                D2  = THREE*(s(i,j,k-1)-TWO*sedgez(i,j,k)+s(i,j,k))
                D2L = s(i,j,k-2)-TWO*s(i,j,k-1)+s(i,j,k)
                D2R = s(i,j,k-1)-TWO*s(i,j,k)+s(i,j,k+1)
                sgn = sign(ONE,D2)
                D2LIM = sgn*max(min(C*sgn*D2L,C*sgn*D2R,sgn*D2),ZERO)
                sedgez(i,j,k) = HALF*(s(i,j,k-1)+s(i,j,k)) - SIXTH*D2LIM
             end if
          end do
       end do
    end do
    !
    ! Use Colella 2008 limiters.
    !
    ! This is a new version of the algorithm to eliminate sensitivity to roundoff.
    !
    k = k3d
    do j=ilo2-1,ihi2+1
       do i=ilo1-1,ihi1+1

          alphap   = sedgez(i,j,k+1)-s(i,j,k)
          alpham   = sedgez(i,j,k  )-s(i,j,k)
          bigp     = abs(alphap).gt.TWO*abs(alpham)
          bigm     = abs(alpham).gt.TWO*abs(alphap)
          extremum = .false.

          if (alpham*alphap .ge. ZERO) then
             extremum = .true.
          else if (bigp .or. bigm) then
             !
             ! Possible extremum. We look at cell centered values and face
             ! centered values for a change in sign in the differences adjacent to
             ! the cell. We use the pair of differences whose minimum magnitude is the
             ! largest, and thus least susceptible to sensitivity to roundoff.
             !
             dafacem   = sedgez(i,j,k) - sedgez(i,j,k-1)
             dafacep   = sedgez(i,j,k+2) - sedgez(i,j,k+1)
             dabarm    = s(i,j,k) - s(i,j,k-1)
             dabarp    = s(i,j,k+1) - s(i,j,k)
             dafacemin = min(abs(dafacem),abs(dafacep))
             dabarmin  = min(abs(dabarm),abs(dabarp))
             if (dafacemin.ge.dabarmin) then
                dachkm = dafacem
                dachkp = dafacep
             else
                dachkm = dabarm
                dachkp = dabarp
             endif
             extremum = (dachkm*dachkp .le. ZERO)
          end if

          if (extremum) then
             D2     = SIX*(alpham + alphap)
             D2L    = s(i,j,k-2)-TWO*s(i,j,k-1)+s(i,j,k)
             D2R    = s(i,j,k)-TWO*s(i,j,k+1)+s(i,j,k+2)
             D2C    = s(i,j,k-1)-TWO*s(i,j,k)+s(i,j,k+1)
             sgn    = sign(ONE,D2)
             D2LIM  = max(min(sgn*D2,C*sgn*D2L,C*sgn*D2R,C*sgn*D2C),ZERO)
             alpham = alpham*D2LIM/max(abs(D2),1.d-10)
             alphap = alphap*D2LIM/max(abs(D2),1.d-10)
          else
             if (bigp) then
                sgn   = sign(ONE,alpham)
                amax  = -alphap**2 / (4*(alpham + alphap))
                delam = s(i,j,k-1) - s(i,j,k)
                if (sgn*amax .ge. sgn*delam) then
                   if (sgn*(delam - alpham).ge.1.d-10) then
                      alphap = (-TWO*delam - TWO*sgn*sqrt(delam**2 - delam*alpham))
                   else 
                      alphap = -TWO*alpham
                   endif
                endif
             end if
             if (bigm) then
                sgn   = sign(ONE,alphap)
                amax  = -alpham**2 / (4*(alpham + alphap))
                delap = s(i,j,k+1) - s(i,j,k)
                if (sgn*amax .ge. sgn*delap) then
                   if (sgn*(delap - alphap).ge.1.d-10) then
                      alpham = (-TWO*delap - TWO*sgn*sqrt(delap**2 - delap*alphap))
                   else
                      alpham = -TWO*alphap
                   endif
                endif
             end if
          end if

          sm = s(i,j,k) + alpham
          sp = s(i,j,k) + alphap

          if (ppm_flatten_before_integrals > 0) then
             ! flatten the parabola AFTER doing the monotonization (note k = k3d here)
             sm = flatn(i,j,k3d)*sm + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
             sp = flatn(i,j,k3d)*sp + (ONE-flatn(i,j,k3d))*s(i,j,k3d)
          endif

          !
          ! Compute z-component of Ip and Im.
          !
          s6    = SIX*s(i,j,k3d) - THREE*(sm+sp)

          
          ! w-c wave
          sigma = abs(u(i,j,k3d,3)-cspd(i,j,k3d))*dtdz
          
          if (u(i,j,k3d,3)-cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,3,1) = sp 
          else
             Ip(i,j,kc,3,1) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,3)-cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,3,1) = sm 
          else
             Im(i,j,kc,3,1) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! w wave
          sigma = abs(u(i,j,k3d,3))*dtdz

          if (u(i,j,k3d,3) <= ZERO) then
             Ip(i,j,kc,3,2) = sp
          else
             Ip(i,j,kc,3,2) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,3) >= ZERO) then
             Im(i,j,kc,3,2) = sm
          else
             Im(i,j,kc,3,2) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

          ! w+c wave
          sigma = abs(u(i,j,k3d,3)+cspd(i,j,k3d))*dtdz

          if (u(i,j,k3d,3)+cspd(i,j,k3d) <= ZERO) then
             Ip(i,j,kc,3,3) = sp 
          else
             Ip(i,j,kc,3,3) = sp - &
                  HALF*sigma*(sp-sm-(ONE-TWO3RD*sigma)*s6)
          endif

          if (u(i,j,k3d,3)+cspd(i,j,k3d) >= ZERO) then
             Im(i,j,kc,3,3) = sm 
          else
             Im(i,j,kc,3,3) = sm + &
                  HALF*sigma*(sp-sm+(ONE-TWO3RD*sigma)*s6)
          endif

       end do
    end do

    call bl_deallocate(sedge)
    call bl_deallocate(sedgez)

  end subroutine ppm_type2

end module ppm_module

