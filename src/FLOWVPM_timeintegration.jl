#=##############################################################################
# DESCRIPTION
    Time integration schemes.

# AUTHORSHIP
  * Author    : Eduardo J Alvarez
  * Email     : Edo.AlvarezR@gmail.com
  * Created   : Aug 2020
=###############################################################################

"""
Steps the field forward in time by dt in a first-order Euler integration scheme.
"""
function euler(pfield::ParticleField{R, <:ClassicVPM, V, <:SubFilterScale, <:Any, <:Any, <:Any},
                                dt::Real; relax::Bool=false, custom_UJ=nothing) where {R, V}

    # Evaluate UJ, SFS, and C
    # NOTE: UJ evaluation is NO LONGER performed inside the SFS scheme
    pfield.SFS(pfield, BeforeUJ())
    if isnothing(custom_UJ)
        pfield.UJ(pfield; reset_sfs=isSFSenabled(pfield.SFS), reset=true, sfs=isSFSenabled(pfield.SFS))
    else
        custom_UJ(pfield; reset_sfs=isSFSenabled(pfield.SFS), reset=true, sfs=isSFSenabled(pfield.SFS))
    end
    pfield.SFS(pfield, AfterUJ())

    # Calculate freestream
    Uinf::Array{<:Real, 1} = pfield.Uinf(pfield.t)

    zeta0::R = pfield.kernel.zeta(0)

    # Update the particle field: convection and stretching
    for p in iterator(pfield)

        C::R = p.var[37]

        # Update position
        p.var[1] += dt*(p.var[10] + Uinf[1])
        p.var[2] += dt*(p.var[11] + Uinf[2])
        p.var[3] += dt*(p.var[12] + Uinf[3])

        # Update vectorial circulation
        ## Vortex stretching contributions
        if pfield.transposed
            # Transposed scheme (Γ⋅∇')U
            p.var[4] += dt*(p.var[16]*p.var[4]+p.var[17]*p.var[5]+p.var[18]*p.var[6])
            p.var[5] += dt*(p.var[19]*p.var[4]+p.var[20]*p.var[5]+p.var[21]*p.var[6])
            p.var[6] += dt*(p.var[22]*p.var[4]+p.var[23]*p.var[5]+p.var[24]*p.var[6])
        else
            # Classic scheme (Γ⋅∇)U
            p.var[4] += dt*(p.var[16]*p.var[4]+p.var[19]*p.var[5]+p.var[22]*p.var[6])
            p.var[5] += dt*(p.var[17]*p.var[4]+p.var[20]*p.var[5]+p.var[23]*p.var[6])
            p.var[6] += dt*(p.var[18]*p.var[4]+p.var[21]*p.var[5]+p.var[24]*p.var[6])
        end

        ## Subfilter-scale contributions -Cϵ where ϵ=(Eadv + Estr)/zeta_sgmp(0)
        p.var[4] -= dt*C*get_SFS1(p) * p.var[7]^3/zeta0
        p.var[5] -= dt*C*get_SFS2(p) * p.var[7]^3/zeta0
        p.var[6] -= dt*C*get_SFS3(p) * p.var[7]^3/zeta0

        # Relaxation: Align vectorial circulation to local vorticity
        if relax
            pfield.relaxation(p)
        end

    end

    # Update the particle field: viscous diffusion
    viscousdiffusion(pfield, dt)

    return nothing
end









"""
Steps the field forward in time by dt in a first-order Euler integration scheme
using the VPM reformulation. See notebook 20210104.
"""
function euler(pfield::ParticleField{R, <:ReformulatedVPM{R2}, V, <:SubFilterScale, <:Any, <:Any, <:Any},
                              dt::Real; relax::Bool=false, custom_UJ=nothing) where {R, V, R2}

    # Evaluate UJ, SFS, and C
    # NOTE: UJ evaluation is NO LONGER performed inside the SFS scheme
    pfield.SFS(pfield, BeforeUJ())
    if isnothing(custom_UJ)
        pfield.UJ(pfield; reset_sfs=isSFSenabled(pfield.SFS), reset=true, sfs=isSFSenabled(pfield.SFS))
    else
        custom_UJ(pfield; reset_sfs=isSFSenabled(pfield.SFS), reset=true, sfs=isSFSenabled(pfield.SFS))
    end
    pfield.SFS(pfield, AfterUJ())
    
    # Calculate freestream
    Uinf::Array{<:Real, 1} = pfield.Uinf(pfield.t)

    MM::Array{<:Real, 1} = pfield.M
    f::R2, g::R2 = pfield.formulation.f, pfield.formulation.g
    zeta0::R = pfield.kernel.zeta(0)

    # Update the particle field: convection and stretching
    for p in iterator(pfield)

        C::R = p.var[37]

        # Update position
        p.var[1] += dt*(p.var[10] + Uinf[1])
        p.var[2] += dt*(p.var[11] + Uinf[2])
        p.var[3] += dt*(p.var[12] + Uinf[3])

        # Store stretching S under MM[1:3]
        if pfield.transposed
            # Transposed scheme S = (Γ⋅∇')U
            MM[1] = (p.var[16]*p.var[4]+p.var[17]*p.var[5]+p.var[18]*p.var[6])
            MM[2] = (p.var[19]*p.var[4]+p.var[20]*p.var[5]+p.var[21]*p.var[6])
            MM[3] = (p.var[22]*p.var[4]+p.var[23]*p.var[5]+p.var[24]*p.var[6])
        else
            # Classic scheme S = (Γ⋅∇)U
            MM[1] = (p.var[16]*p.var[4]+p.var[19]*p.var[5]+p.var[22]*p.var[6])
            MM[2] = (p.var[17]*p.var[4]+p.var[20]*p.var[5]+p.var[23]*p.var[6])
            MM[3] = (p.var[18]*p.var[4]+p.var[21]*p.var[5]+p.var[24]*p.var[6])
        end

        # Store Z under MM[4] with Z = [ (f+g)/(1+3f) * S⋅Γ - f/(1+3f) * Cϵ⋅Γ ] / mag(Γ)^2, and ϵ=(Eadv + Estr)/zeta_sgmp(0)
        MM[4] = (f+g)/(1+3*f) * (MM[1]*p.var[4] + MM[2]*p.var[5] + MM[3]*p.var[6])
        MM[4] -= f/(1+3*f) * (C*get_SFS1(p)*p.var[4] + C*get_SFS2(p)*p.var[5] + C*get_SFS3(p)*p.var[6]) * p.var[7]^3/zeta0
        MM[4] /= p.var[4]^2 + p.var[5]^2 + p.var[6]^2

        # Update vectorial circulation ΔΓ = Δt*(S - 3ZΓ - Cϵ)
        p.var[4] += dt * (MM[1] - 3*MM[4]*p.var[4] - C*get_SFS1(p)*p.var[7]^3/zeta0)
        p.var[5] += dt * (MM[2] - 3*MM[4]*p.var[5] - C*get_SFS2(p)*p.var[7]^3/zeta0)
        p.var[6] += dt * (MM[3] - 3*MM[4]*p.var[6] - C*get_SFS3(p)*p.var[7]^3/zeta0)

        # Update cross-sectional area of the tube σ = -Δt*σ*Z
        p.var[7] -= dt * ( p.var[7] * MM[4] )

        # Relaxation: Alig vectorial circulation to local vorticity
        if relax
            pfield.relaxation(p)
        end

    end

    # Update the particle field: viscous diffusion
    viscousdiffusion(pfield, dt)
    
    return nothing
end












"""
Steps the field forward in time by dt in a third-order low-storage Runge-Kutta
integration scheme. See Notebook entry 20180105.
"""
function rungekutta3(pfield::ParticleField{R, <:ClassicVPM, V, <:SubFilterScale, <:Any, <:Any, <:Any},
                            dt::Real; relax::Bool=false, custom_UJ=nothing) where {R, V}

    # Storage terms: qU <=> p.M[:, 1], qstr <=> p.M[:, 2], qsmg2 <=> p.var[34]

    # Calculate freestream
    Uinf::Array{<:Real, 1} = pfield.Uinf(pfield.t)

    zeta0::R = pfield.kernel.zeta(0)

    # Reset storage memory to zero
    zeroR::R = zero(R)
    for p in iterator(pfield); p.var[28:36] .= zeroR; end;

    # Runge-Kutta inner steps
    for (a,b) in (R.((0, 1/3)), R.((-5/9, 15/16)), R.((-153/128, 8/15)))

        # Evaluate UJ, SFS, and C
        # NOTE: UJ evaluation is NO LONGER performed inside the SFS scheme
        pfield.SFS(pfield, BeforeUJ(); a=a, b=b)
        if isnothing(custom_UJ)
            pfield.UJ(pfield; reset_sfs=true, reset=true, sfs=true)
        else
            custom_UJ(pfield; reset_sfs=true, reset=true, sfs=true)
        end
        pfield.SFS(pfield, AfterUJ(); a=a, b=b)

        # Update the particle field: convection and stretching
        for p in iterator(pfield)

            C::R = p.var[37]

            # Low-storage RK step
            ## Velocity
            p.var[28] = a*p.var[28] + dt*(p.var[10] + Uinf[1])
            p.var[29] = a*p.var[29] + dt*(p.var[11] + Uinf[2])
            p.var[30] = a*p.var[30] + dt*(p.var[12] + Uinf[3])

            # Update position
            p.var[1] += b*p.var[28]
            p.var[2] += b*p.var[29]
            p.var[3] += b*p.var[30]

            ## Stretching + SFS contributions
            if pfield.transposed
                # Transposed scheme (Γ⋅∇')U - Cϵ where ϵ=(Eadv + Estr)/zeta_sgmp(0)
                p.var[31] = a*p.var[31] + dt*(p.var[16]*p.var[4]+p.var[17]*p.var[5]+p.var[18]*p.var[6] - C*get_SFS1(p)*p.var[7]^3/zeta0)
                p.var[32] = a*p.var[32] + dt*(p.var[19]*p.var[4]+p.var[20]*p.var[5]+p.var[21]*p.var[6] - C*get_SFS2(p)*p.var[7]^3/zeta0)
                p.var[33] = a*p.var[33] + dt*(p.var[22]*p.var[4]+p.var[23]*p.var[5]+p.var[24]*p.var[6] - C*get_SFS3(p)*p.var[7]^3/zeta0)
            else
                # Classic scheme (Γ⋅∇)U - Cϵ where ϵ=(Eadv + Estr)/zeta_sgmp(0)
                p.var[31] = a*p.var[31] + dt*(p.var[16]*p.var[4]+p.var[19]*p.var[5]+p.var[22]*p.var[6] - C*get_SFS1(p)*p.var[7]^3/zeta0)
                p.var[32] = a*p.var[32] + dt*(p.var[17]*p.var[4]+p.var[20]*p.var[5]+p.var[23]*p.var[6] - C*get_SFS2(p)*p.var[7]^3/zeta0)
                p.var[33] = a*p.var[33] + dt*(p.var[18]*p.var[4]+p.var[21]*p.var[5]+p.var[24]*p.var[6] - C*get_SFS3(p)*p.var[7]^3/zeta0)
            end

            # Update vectorial circulation
            p.var[4] += b*p.var[31]
            p.var[5] += b*p.var[32]
            p.var[6] += b*p.var[33]

        end

        # Update the particle field: viscous diffusion
        viscousdiffusion(pfield, dt; aux1=a, aux2=b)

    end


    # Relaxation: Align vectorial circulation to local vorticity
    if relax

        # Resets U and J from previous step
        _reset_particles(pfield)

        # Calculates interactions between particles: U and J
        # NOTE: Technically we have to calculate J at the final location,
        #       but in MyVPM I just used the J calculated in the last RK step
        #       and it worked just fine. So maybe I perhaps I can save computation
        #       by not calculating UJ again.
        pfield.UJ(pfield)

        for p in iterator(pfield)
            # Align particle strength
            pfield.relaxation(p)
        end
    end

    return nothing
end












"""
Steps the field forward in time by dt in a third-order low-storage Runge-Kutta
integration scheme using the VPM reformulation. See Notebook entry 20180105
(RK integration) and notebook 20210104 (reformulation).
"""
function rungekutta3(pfield::ParticleField{R, <:ReformulatedVPM{R2}, V, <:SubFilterScale, <:Any, <:Any, <:Any},
                     dt::Real; relax::Bool=false, custom_UJ=nothing) where {R, V, R2}

    # Storage terms: qU <=> p.M[:, 1], qstr <=> p.M[:, 2], qsmg2 <=> p.var[34],
    #                      qsmg <=> p.var[35], Z <=> MM[4], S <=> MM[1:3]

    # Calculate freestream
    Uinf::Array{<:Real, 1} = pfield.Uinf(pfield.t)

    MM::Array{<:Real, 1} = pfield.M
    f::R2, g::R2 = pfield.formulation.f, pfield.formulation.g
    zeta0::R = pfield.kernel.zeta(0)

    # Reset storage memory to zero
    zeroR::R = zero(R)
    for p in iterator(pfield); p.var[28:36] .= zeroR; end;

    # Runge-Kutta inner steps
    for (a,b) in (R.((0, 1/3)), R.((-5/9, 15/16)), R.((-153/128, 8/15)))

        # Evaluate UJ, SFS, and C
        # NOTE: UJ evaluation is NO LONGER performed inside the SFS scheme
        pfield.SFS(pfield, BeforeUJ(); a=a, b=b)
        if isnothing(custom_UJ)
            pfield.UJ(pfield; reset_sfs=true, reset=true, sfs=true)
        else
            custom_UJ(pfield; reset_sfs=true, reset=true, sfs=true)
        end
        pfield.SFS(pfield, AfterUJ(); a=a, b=b)

        # Update the particle field: convection and stretching
        for p in iterator(pfield)

            C::R = p.var[37]

            # Low-storage RK step
            ## Velocity
            p.var[28] = a*p.var[28] + dt*(p.var[10] + Uinf[1])
            p.var[29] = a*p.var[29] + dt*(p.var[11] + Uinf[2])
            p.var[30] = a*p.var[30] + dt*(p.var[12] + Uinf[3])

            # Update position
            p.var[1] += b*p.var[28]
            p.var[2] += b*p.var[29]
            p.var[3] += b*p.var[30]

            # Store stretching S under M[1:3]
            if pfield.transposed
                # Transposed scheme S = (Γ⋅∇')U
                MM[1] = p.var[16]*p.var[4]+p.var[17]*p.var[5]+p.var[18]*p.var[6]
                MM[2] = p.var[19]*p.var[4]+p.var[20]*p.var[5]+p.var[21]*p.var[6]
                MM[3] = p.var[22]*p.var[4]+p.var[23]*p.var[5]+p.var[24]*p.var[6]
            else
                # Classic scheme (Γ⋅∇)U
                MM[1] = p.var[16]*p.var[4]+p.var[19]*p.var[5]+p.var[22]*p.var[6]
                MM[2] = p.var[17]*p.var[4]+p.var[20]*p.var[5]+p.var[23]*p.var[6]
                MM[3] = p.var[18]*p.var[4]+p.var[21]*p.var[5]+p.var[24]*p.var[6]
            end

            # Store Z under MM[4] with Z = [ (f+g)/(1+3f) * S⋅Γ - f/(1+3f) * Cϵ⋅Γ ] / mag(Γ)^2, and ϵ=(Eadv + Estr)/zeta_sgmp(0)
            MM[4] = (f+g)/(1+3*f) * (MM[1]*p.var[4] + MM[2]*p.var[5] + MM[3]*p.var[6])
            MM[4] -= f/(1+3*f) * (C*get_SFS1(p)*p.var[4] + C*get_SFS2(p)*p.var[5] + C*get_SFS3(p)*p.var[6]) * p.var[7]^3/zeta0
            MM[4] /= p.var[4]^2 + p.var[5]^2 + p.var[6]^2

            # Store qstr_i = a_i*qstr_{i-1} + ΔΓ,
            # with ΔΓ = Δt*( S - 3ZΓ - Cϵ )
            p.var[31] = a*p.var[31] + dt*(MM[1] - 3*MM[4]*p.var[4] - C*get_SFS1(p)*p.var[7]^3/zeta0)
            p.var[32] = a*p.var[32] + dt*(MM[2] - 3*MM[4]*p.var[5] - C*get_SFS2(p)*p.var[7]^3/zeta0)
            p.var[33] = a*p.var[33] + dt*(MM[3] - 3*MM[4]*p.var[6] - C*get_SFS3(p)*p.var[7]^3/zeta0)

            # Store qsgm_i = a_i*qsgm_{i-1} + Δσ, with Δσ = -Δt*σ*Z
            p.var[35] = a*p.var[35] - dt*( p.var[7] * MM[4] )

            # Update vectorial circulation
            p.var[4] += b*p.var[31]
            p.var[5] += b*p.var[32]
            p.var[6] += b*p.var[33]

            # Update cross-sectional area
            p.var[7] += b*p.var[35]

        end

        # Update the particle field: viscous diffusion
        viscousdiffusion(pfield, dt; aux1=a, aux2=b)

    end


    # Relaxation: Align vectorial circulation to local vorticity
    if relax

        # Resets U and J from previous step
        _reset_particles(pfield)

        # Calculates interactions between particles: U and J
        # NOTE: Technically we have to calculate J at the final location,
        #       but in MyVPM I just used the J calculated in the last RK step
        #       and it worked just fine. So maybe I perhaps I can save computation
        #       by not calculating UJ again.
        pfield.UJ(pfield)

        for p in iterator(pfield)
            # Align particle strength
            pfield.relaxation(p)
        end
    end

    return nothing
end
